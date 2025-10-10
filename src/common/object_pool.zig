//! Its a pool that works like a pool with handle indexing. Good for DOD
//! centralized data storage in da memory. This is the cornerstone
//! of the memory management sytem for this application.
//!
//! TODO: A great feature would be adding scoped allocations for individual pools
//! which match vulkan object's lifetimes (generally they are the same per-type of object)

const std = @import("std");
const common = @import("common.zig");
const builtin = @import("builtin");
const debug = std.debug;

const Allocator = std.mem.Allocator;
const AnyPtr = common.AnyPtr;
const Alignment = std.mem.Alignment;

const Self = @This();

const PoolError = error{
    OutOfMemory,
    InvalidHandle,
};

const Config = struct {
    /// Leave null for default type alignment
    alignment: ?std.mem.Alignment = null,
    /// Leave null for 32-bit indexing and equal generation counter.
    IndexType: type = u32,
    /// Can pool expand once existing resources are exhausted?
    /// NOTE: This is a little janky in implenmentation for the moment
    growable: bool = true,
};

// I didn't plan this out at all lol
// Plan:
// Step 1: Handles and slots are stored in separate blocks, indexed as slices in the header
//  (this is to decrease alignment padding bytes)
// Step 1.1: 
// Step 2: Memory broken into pages (done)
// Step 3: Pages can be created if more space is needed and growing is allowed (done)


/// Finds the address offset between 2 separately alignments, 
/// i.e the padding bytes required.
fn alignForwardDiff(comptime T: type, comptime b: Alignment) comptime_int {
    // @compileLog(@typeName(T));
    // @compileLog(@sizeOf(T));
    // @compileLog(b.toByteUnits());
    return @sizeOf(T) % b.toByteUnits();
}

///TODO: Handle bit widths smaller then a single page
fn PartitionIndexType(comptime IndexType: type, page_size: usize) type {
    _ = page_size;

    const low_bits = 12;
    const high_bits = @typeInfo(IndexType).int.bits - low_bits;


    return packed struct {
        page_index: std.meta.Int(.unsigned, high_bits),
        addr: std.meta.Int(.unsigned, low_bits),
    };


}

/// Type Safe generic pool
/// Note that signedness is unsupported in config since there is no point
/// in supporting negative indexing
pub fn ObjectPool(comptime T: type, comptime config: Config) type {
    if (@typeInfo(config.IndexType) != .int) 
        @compileError("IndexType must be an integer");
    if (@typeInfo(config.IndexType).int.bits < 12) 
        @compileError("IndexType must have a bit-width of at least 12");
    if (@typeInfo(config.IndexType).int.signedness != .unsigned)
        @compileError("IndexType must be unsigned");



    const resolved_alignment = if (config.alignment) |al|
        al
    else
        Alignment.fromByteUnits(@alignOf(T));

    return struct {
        pub const IndexType = config.IndexType;
        /// needs to accomodate free list nodes at least...
        const SlotType = if (@sizeOf(T) > @sizeOf(FreeNode)) T else FreeNode;
        const Pool = @This();

        const FreeNode = struct {
            next: ?*FreeNode,
            page: *Page,
        };

        pub const Handle = common.Handle(T, .{
            .index_bits = @typeInfo(config.IndexType).int.bits,
            .gen_bits = @typeInfo(config.IndexType).int.bits,
            .partition_bit = 12,
        });

        fn getReified(p: *anyopaque, h: Handle) PoolError!*T {
            const pool: *Pool = @ptrCast(@alignCast(p));
            return pool.get(h);
        }

        pub const ReifiedHandle = Handle.Reified(PoolError, getReified);
            
        // These 2 functions are meant to update state in the stored handle state 
        // of the pool, not the handles the user gets
        fn bind(h: *Handle, idx: usize, page_index: usize) void {
            debug.assert(idx < std.math.maxInt(IndexType));
            debug.assert(page_index < std.math.maxInt(IndexType));

            h.index.lhs = @intCast(idx);
            h.index.rhs = @intCast(page_index);
        }

        fn unbind(h: *Handle) void {
            h.index.lhs = 0;
            h.index.rhs = 0;
            h.gen += 1;
        }

        /// Pages are broken into 2 separately alligned sections of memory
        /// - Handles (contiains handle information mainly gen count)
        /// - Slots (contains actual data for the object stuff)
        ///
        /// Both are forwards aligned to their natural aligned addresses
        /// for minimal padding due to a disjoint in the alignment of handles
        /// and the container type
        const Page = struct {
            cap: usize = page_size,
            index: usize,
            handles: [*]Handle, // to prevent gross pointer arithmetic
            slots: [*]SlotType,
        };

        const PageArray = std.ArrayListUnmanaged(*Page);

        pub const page_size = 4096;
        const handle_align_padding = alignForwardDiff(
            Page, 
            Alignment.fromByteUnits(@alignOf(Handle)),
        );
        const slot_align_padding = alignForwardDiff(Handle, resolved_alignment);

        free_list: ?*FreeNode = null,
        allocator: Allocator,

        page_table: PageArray,

        // tracks the currently growing page in the allocator (for reuse purposes)
        current_page: usize = 0,

        fn prependFreeNode(pool: *Pool, node: *FreeNode) void {
            node.next = pool.free_list;
            pool.free_list = node;
        }

        fn popFreeNode(pool: *Pool) ?*FreeNode {
            const free_node = pool.free_list;

            if (pool.free_list) |fl| {
                pool.free_list = fl.next;
            }

            return free_node;
        }

        fn growPageIfAllowed(pool: *Pool) PoolError!*Page {
            if (!config.growable) return error.OutOfMemory;
            return pool.justGrowTheFuckingPage(page_size);
        }

        fn indexForNode(node: *FreeNode) usize {
            const relative_addr = @intFromPtr(node) - @intFromPtr(node.page.slots);
            return @divExact(relative_addr, @sizeOf(SlotType));
        }
        
        /// Ensures there's enough capacity without altering
        /// the free list
        fn ensureCapacity(pool: *Pool, cap: usize) PoolError!void {
            var current_cap: usize = 0;
            for (pool.page_table.items) |page| {
                current_cap += page.cap;
            }

            if (current_cap >= cap) return;

            const needed_cap = cap - current_cap;
            const needed_pages = @divFloor(needed_cap, page_size) + 1;
            
            var p: *Page = undefined;
            for (0..needed_pages) |_| {
                p = try pool.justGrowTheFuckingPage(page_size);
            }
            
            // Lower the final page's capacity
            // So OutOfMemory happens when expected
            p.cap = needed_cap % page_size;
        }

        inline fn calcAllocationSize(size: usize) usize {
            return size * @sizeOf(Handle) + size * @sizeOf(SlotType) + @sizeOf(Page) +
                handle_align_padding + slot_align_padding;
        }

        fn justGrowTheFuckingPage(pool: *Pool, size: usize) PoolError!*Page {
            // If we have an extra unused page, just return that instead.
            // This covers the cases of pool reuse via the .reset() method
            if (pool.page_table.items.len != 0 and 
                pool.page_table.items.len - 1 > pool.current_page) {
                return pool.page_table.items[pool.current_page + 1];
            }
            const allocation_size = calcAllocationSize(size);

            const new_page = try pool.allocator.alignedAlloc(
                u8, 
                @alignOf(Page), 
                allocation_size,
            );
            errdefer pool.allocator.free(new_page);

            const page_ptr = @as(*Page, @ptrCast(new_page.ptr));

            const handles_addr: [*]Handle = 
                @ptrFromInt(@intFromPtr(page_ptr) + 
                @sizeOf(Page) + handle_align_padding
            );


            const slots_addr: [*]SlotType = @ptrFromInt(
                @intFromPtr(handles_addr) + 
                page_size * @sizeOf(Handle) + slot_align_padding
            );

            page_ptr.* = .{
                .handles = handles_addr,
                .slots = slots_addr,
                .index = pool.page_table.items.len,
            };

            try pool.page_table.append(pool.allocator, page_ptr); 
            return page_ptr;
        }
        
        /// yeet a new free node onto the free list
        pub fn allocNew(pool: *Pool) PoolError!*FreeNode {
            var current_page = pool.page_table.items[pool.current_page];
            if (current_page.cap == 0) {
                current_page = try pool.growPageIfAllowed();
                pool.current_page += 1;
            }

            const next_index = current_page.cap - 1;
            const node: *FreeNode = @ptrCast(@alignCast(&current_page.slots[next_index]));
            node.page = current_page;

            current_page.cap -= 1;
            return node;
        }

        /// Initialize the thing
        /// A non growable pool should use initPreheated since no pool memory
        /// is allocated aside from the page table in this function
        pub fn init(allocator: Allocator, initial_size: usize) PoolError!Pool {
            var pool = Pool{
                // This is completely arbitrary
                .page_table = try PageArray.initCapacity(allocator, 32),
                .allocator = allocator,
            };
            
            try pool.ensureCapacity(initial_size);

            return pool;
        }

        /// Initialize the thing with cap guaranteed free slots before next allocation
        pub fn initPreheated(allocator: Allocator, cap: usize) PoolError!Pool {
            var new_pool = try init(allocator, cap);
            try new_pool.ensureCapacity(cap);
            new_pool.preheat(cap) catch unreachable;

            return new_pool;
        }

        pub fn preheat(pool: *Pool, cap: usize) PoolError!void {
            for (0..cap) |_| {
                const node = try pool.allocNew();
                pool.prependFreeNode(node);
            }
        }

        fn fetchPageIfValid(pool: *Pool, h: Handle) PoolError!*Page {
            debug.assert(h.index.rhs <= pool.page_table.items.len);
            const page = pool.page_table.items[h.index.rhs];

            const handle = page.handles[h.index.lhs];
            if (h.gen != handle.gen) return error.InvalidHandle;

            return page;
        }
        
        // get an element outta the pool
        pub fn get(pool: *Pool, h: Handle) PoolError!*T {
            const page = try pool.fetchPageIfValid(h);
            return @as(*T, @ptrCast(@alignCast(&page.slots[h.index.lhs])));
        }
        
        /// reserve a single handle and allocate if needed
        pub fn reserve(pool: *Pool) PoolError!Handle {
            var node = pool.popFreeNode() orelse 
                try pool.allocNew();

            const index = indexForNode(node);

            const handle = &node.page.handles[index];
            bind(handle, index, @intCast(node.page.index));

            return handle.*;
        }
        
        /// Reserve an item from the poool and initialize it with the givne value
        pub fn reserveInit(pool: *Pool, val: T) PoolError!Handle {
            const h = try pool.reserve();
            const v = pool.get(h) catch unreachable;
            v.* = val;

            return h;
        }

        /// Reserve an item and retain memory of which pool allocated it in the handle
        /// (essentially "reifying the handle" by 
        /// giving all the information needed to resolve the data)
        pub fn reserveReified(pool: *Pool) PoolError!ReifiedHandle {
            const h = try pool.reserve();
            return ReifiedHandle.init(h, pool);
        }

        pub fn reserveAssumeCapacityReified(pool: *Pool) ReifiedHandle {
            const h = pool.reserveAssumeCapacity();
            return ReifiedHandle.init(h, pool);
        }

        /// reserve a single handle whilst assuming there is space
        /// Useful if you know that the pool will have space for a reservation
        /// and you don't want to deal with an unreachable failure point
        /// ... Of course, it should actually be unreachable...
        pub fn reserveAssumeCapacity(pool: *Pool) Handle {
            var node = pool.popFreeNode() orelse unreachable;
            const index = indexForNode(node);
            
            const handle = &node.page.handles[index];
            bind(handle, index, node.page.index);

            return handle.*;
        }

        pub fn reserveAssumeCapacityInit(pool: *Pool, val: *const T) Handle {
            const h = pool.reserveAssumeCapacity();
            const v = pool.get(h) orelse unreachable;

            v.* = val.*;
            return h;
        }
        

        /// return a handle to the pool, freeing it.
        pub fn free(pool: *Pool, h: Handle) void {
            const page = pool.fetchPageIfValid(h) catch return;
            const backing_h = &page.handles[h.index.lhs];
            const former_slot: *FreeNode = @ptrCast(&page.slots[h.index.lhs]);
            
            unbind(backing_h);
            pool.prependFreeNode(former_slot);
        } 

        /// reset the pool's allocations but don't bother freeing the backing memory
        /// BUG: This function is completely BORKED, lemme fix it later
        pub fn reset(pool: *Pool) void {
            for (pool.page_table.items) |page| {
                page.cap = page_size;
            }
            pool.current_page = 0;

            pool.free_list = pool.allocNew() catch unreachable; 
        }
        
        /// Destroy the entire pool and free all the memory
        pub fn deinit(pool: *Pool) void {
            const allocation_size = calcAllocationSize(page_size);
            for (pool.page_table.items) |page| {
                const original_slice: []u8 = @as([*]u8, @ptrCast(@alignCast(page)))[0..allocation_size];
                pool.allocator.free(original_slice);
            }

            pool.page_table.deinit(pool.allocator);
        }
    };
}

const testing = std.testing;

const TestingTypeA = [10]u32;

test "out of memory" {

    var pool = try ObjectPool(TestingTypeA, .{.growable = false}).init(testing.allocator, 2);
    defer pool.deinit();

    for (0..2) |_| {
        _ = try pool.reserve();
    }

    try testing.expectError(error.OutOfMemory, pool.reserve()); 

    
    try testing.expectError(error.OutOfMemory, ObjectPool(usize, .{}).init(
        testing.failing_allocator, 
        10,
    ));
}

test "preheat" {
    var pool = try ObjectPool(TestingTypeA, .{.growable = false}).initPreheated(testing.allocator, 32); 
    defer pool.deinit();
    
    for (0..32) |_| {
        _ = pool.reserveAssumeCapacity();
    }

    try testing.expectError(error.OutOfMemory, pool.reserve());

    var pool2 = try ObjectPool(TestingTypeA, .{}).initPreheated(testing.allocator, 10);
    defer pool2.deinit();
    //try pool2.preheat(10);

    for (0..10) |_| {
        _ = pool2.reserveAssumeCapacity();
    }
}

test "growable pool" {
    const TestingTypeB = struct {
        name: []const u8,
        age: usize,
    };

    var pool = try ObjectPool(TestingTypeB, .{}).init(testing.allocator, 1);
    defer pool.deinit();


    for (0..5000) |_| {
        _ = try pool.reserve();
    }

    const h = try pool.reserveInit(.{
        .name = "Jerry Smith",
        .age = 420690,
    });

    try testing.expectEqual((try pool.get(h)).*, TestingTypeB{
        .name = "Jerry Smith",
        .age = 420690,
    });
}

test "integrity" {
    var pool = try ObjectPool(TestingTypeA, .{}).init(testing.allocator, 1024);
    defer pool.deinit();

    const h = try pool.reserveInit(.{0, 1, 2, 3, 4, 5, 6, 7, 8, 9});
    const v = try pool.get(h);

    try testing.expectEqual(v.*, TestingTypeA{0, 1, 2, 3, 4, 5, 6, 7, 8, 9});

    var h2 = h;
    h2.gen += 102313;
    
    try testing.expectError(error.InvalidHandle, pool.get(h2));
}


test "small object allocations" {
    const Smol = u8;
    const HandleType = ObjectPool(Smol, .{}).Handle;
    var handles: [1024]HandleType = undefined;

    var pool = try ObjectPool(Smol, .{}).init(testing.allocator, handles.len);
    defer pool.deinit();


    for (0..handles.len) |i| {
        const val: u8 = @intCast(@mod(i, std.math.maxInt(u8)));
        handles[i] = try pool.reserveInit(val);

        try testing.expectEqual((try pool.get(handles[i])).*, val);
    }

    for (0..handles.len) |i| {
        pool.free(handles[i]);
        try testing.expectError(error.InvalidHandle, pool.get(handles[i]));
    }

}

test "use after free" {
    var pool = try ObjectPool(u32, .{.growable = false}).init(testing.allocator, 10);
    defer pool.deinit();

    const h1 = try pool.reserveInit(42069);
    try testing.expectEqualDeep((try pool.get(h1)).*, @as(u32, 42069));

    pool.free(h1);
    try testing.expectError(error.InvalidHandle, pool.get(h1));

    const h2 = try pool.reserveInit(80085);
    try testing.expectEqual((try pool.get(h2)).*, @as(u32, 80085));

    //pool.reset();
    //try pool.preheat(20);

    //try testing.expectError(error.InvalidHandle, pool.get(h2)); 
}

test "reification" {
    const TestStruct = struct {
        name: []const u8,
        id: usize,
    };
    var pool = try ObjectPool(TestStruct, .{.growable = false}).init(testing.allocator, 128);
    defer pool.deinit();

    const h = try pool.reserveInit(.{
        .name = "larry the libster",
        .id = 932932,
    });

    const h2 = ObjectPool(TestStruct, .{.growable = false}).ReifiedHandle.init(h, &pool);

    try testing.expectEqual(try pool.get(h), try h2.get());
}
