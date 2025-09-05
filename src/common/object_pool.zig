//! Its a pool that works like a pool with handle indexing. Good for DOD
//! centralized data storage in da memory. This is the cornerstone
//! of the memory management sytem for this application.
//!
//! TODO: A great feature would be adding scoped allocations for individual pools
//! which match vulkan object's lifetimes (generally they are the same per-type of object)

const std = @import("std");
const common = @import("common");
const builtin = @import("builtin");
const assert = std.debug.assert;

const Allocator = std.mem.Allocator;
const AnyPtr = common.AnyPtr;
const Alignment = std.mem.Alignment;

const Self = @This();

const PoolError = error{
    OutOfMemory,
    InvalidHandle,
    OutOfBounds,
};

const TypedPoolConfig = struct {
    /// Leave null for default type alignment
    alignment: ?std.mem.Alignment = null,
    /// Leave null for 32-bit indexing and equal generation counter.
    IndexType: type = u32,
    /// Can pool expand once existing resources are exhausted?
    /// NOTE: THis is a little janky in implenmentation for the moment
    growable: bool = false,
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
    return b.toByteUnits() - (@sizeOf(T) % b.toByteUnits());
}

///TODO: Handle bit widths smaller then a single page
fn PartitionIndexType(comptime IndexType: type, page_size: usize) type {
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
pub fn ObjectPool(comptime T: type, comptime config: TypedPoolConfig) type {
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

        pub const Handle = packed struct {
            pub const PartitionedIndex = PartitionIndexType(IndexType, page_size);
            index: PartitionedIndex,
            gen: IndexType,
            
            // These 2 functions are meant to update state in the stored handle state 
            // of the pool, not the handles the user gets
            pub fn bind(h: *Handle, idx: IndexType, page_index: IndexType) void {
                h.index.addr = @intCast(index);
                h.index.page_index = @intCast(page_index);
            }

            pub fn unbind(h: *Handle) void {
                h.index.addr = 0;
                h.index.page_index = 0;
                h.gen += 1;
            }
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
                pool.free_list = pool.free_list.next;
            }

            return free_node;
        }

        fn growPageIfAllowed(pool: *Pool) PoolError!*Page {
            if (!config.growable) return error.OutOfMemory;
            return self.justGrowTheFuckingPage(page_size);
        }

        fn indexForNode(node: *FreeNode) usize {
            const relative_addr = @intFromPtr(node) - @intFromPtr(node.page.slots.ptr);
            return @divExact(relative_addr, @sizeOf(SlotType));
        }
        
        /// Ensures there's enough capacity without altering
        /// the free list
        fn ensureCapacity(pool: *Pool, cap: usize) PoolError!void {
            var current_cap = 0;
            for (pool.page_table) |page| {
                current_cap += page.cap;
            }

            if (current_cap >= cap) return;

            const needed_cap = cap - current_cap;
            const needed_pages = @divFloor(needed_cap, page_size) + 1;

            for (0..needed_pages) |_| {
                pool.justGrowTheFuckingPage(page_size);
            }
        }

        fn justGrowTheFuckingPage(pool: *Pool, size: usize) PoolError!*Page {
            // If we have an extra unused page, just return that instead.
            // This covers the cases of pool reuse via the .reset() method
            if (pool.page_table.items.len - 1 > pool.current_page) {
                return &pool.page_table.items[pool.current_page + 1];
            }
            const allocation_size = size * @sizeOf(SlotType) + 
                handle_align_padding + slot_align_padding);

            const new_page = try pool.allocator.allocAligned(
                u8, 
                @alignOf(Page), 
                allocation_size,
            );
            errdefer pool.allocator.free(new_page);

            const page_ptr = @as(*Page, @ptrCast(new_page.ptr));

            const handles_addr: [*]Handle = 
                @ptrFromInt(@intFromPtr(base_addr) + 
                @sizeOf(Page) + handle_align_padding
            );

            const slots_addr: [*]SlotType = @ptrFromInt(
                @intFromPtr(handles_addr) + 
                page_size * @sizeOf(SlotType) + slot_align_padding
            );

            page_ptr.* = .{
                .handles = handles_addr,
                .slots = slots_addr,
                .index = pool.page_table.len,
            };

            try pool.page_table.append(page_ptr, self.allocator);
            return page_ptr;
        }
        
        /// yeet a new free node onto the free list
        pub fn allocNew(pool: *Pool) PoolError!*FreeNode {
            var current_page = &pool.page_table.items[pool.current_page];
            if (current_page.cap == 0) {
                current_page = try self.growPageIfAllowed();
                pool.current_page += 1;
            }

            const next_index = page_size - current_page.cap;
            const node: *FreeNode = @ptrCast(&current_page.slots[next_index]);
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
            
            if (config.growable) {
                try pool.ensureCapacity(initial_size);
            }

            return pool;
        }

        /// Initialize the thing with cap guaranteed free slots before next allocation
        pub fn initPreheated(allocator: Allocator, cap: usize) PoolError!Pool {
            var new_pool = try init(allocator);
            try new_pool.preheat(cap);

            return new_pool;
        }

        pub fn preheat(pool: *Pool, cap: usize) PoolError!void {
            for (0..cap) |i| {
                const node  = try pool.allocNew();
                pool.prependFreeNode(node);
            }
        }

        fn fetchPageIfValid(pool *Pool, h: Handle) PoolError!*Page {
            if (builtin.mode == .ReleaseSafe or builtin.mode == .Debug) {
                if (h.index.page_index > pool.page_table.items.len)
                    return error.OutOfBounds;
            }

            const page = &pool.page_table[h.index.page_index];

            const handle = page.handles[h.index.addr];
            if (h.gen != handle.gen) return error.InvalidHandle;

            return page;
        }
        
        // get an element outta the pool
        pub fn get(pool: *Pool, h: Handle) PoolError!*T {
            const page = try pool.fetchPageIfValid(h);
            return &page.slots[h.index.addr];
        }
        
        /// reserve a single handle and allocate if needed
        pub fn reserve(pool: *Pool) PoolError!Handle {
            var node = pool.popFree() orelse 
                pool.allocNew();

            const index = pool.indexForNode(node);

            const handle = &node.page.handles[index];
            handle.bind(index, node.page.index);

            return handle.*;
        }
        
        /// Reserve an item from the poool and initialize it with the givne value
        pub fn reserveInit(pool: *Pool, val: *const T) PoolError!Handle {
            const h = try pool.reserve();
            const v = pool.get(h) orelse unreachable;
            v.* = val.*;

            return h;
        }

        /// reserve a single handle whilst assuming there is space
        /// Useful if you know that the pool will have space for a reservation
        /// and you don't want to deal with an unreachable failure point
        /// ... Of course, it should actually be unreachable...
        pub fn reserveAssumeCapacity(pool: *Pool) Handle {
            var node = pool.popFree() orelse unreachable;
            const index = pool.indexForNode(node);
            
            const handle = &node.page.handles[index];
            handle.bind(index, node.page.index);

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
            const page = pool.fetchPageIfValid(h);
            const h = &page.handles[h.index.addr];
            const former_slot: *FreeNode = @ptrCast(&page.slots[h.index.addr]);
            
            h.unbind();
            pool.prependFreeNode(former_slot);
        } 

        /// reset the pool's allocations but don't bother freeing the backing memory
        pub fn reset(pool: *Pool) void {
            for (pool.page_table.items) |*page| {
                page.cap = page_size;
            }
            pool.current_page = 0;

            pool.free_list = pool.allocNew() catch unreachable; 
        }
        
        /// Destroy the entire pool and free all the memory
        pub fn deinit(pool: *Pool) void {
            for (pool.page_table) |*page| {
                pool.allocator.free(page);
            }

            pool.page_table.deinit(pool.allocator);
        }
    };
}

