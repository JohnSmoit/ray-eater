//! Takes in a fixed, preallocated
//! buffer of memory and manages it as a pool of
//! a given type of objects to be allocated and freed independently.
//!
//! Free space will be tracked as a RB tree (or maybe a buddy allocator dunno)
//! and alignment requirements and backing allocators (to create the buffer) can be specified at
//! initialization time...
//!
//! Pools contain a fixed capacity that CANNOT be modified unless the pool is later resized,
//! which will probably have a buch of bad side effects that make it not really that good of an idea
//! (i.e invalidates everything so all pointers to handles are not guaranteed).
//!
//! TODO: A great feature would be adding scoped allocations for individual pools
//! which match vulkan object's lifetimes (generally they are the same per-type of object)

const std = @import("std");
const common = @import("common");
const assert = std.debug.assert;

const Allocator = std.mem.Allocator;
const AnyPtr = common.AnyPtr;

const Self = @This();

const PoolError = error{
    OutOfMemory,
    InvalidHandle,
};

const TypedPoolConfig = struct {
    index_bits: usize = 32,
    generation_bits: usize = 32,
    growable: bool = false,
};

// I didn't plan this out at all lol
// Plan:
// Step 1: 2 regions per page: handle and object storage
// Step 2: Memory broken into pages (done)
// Step 3: Pages can be created if more space is needed and growing is allowed (done)
// Step 4: Profit (never happening)

/// Type Safe generic pool
pub fn TypedPool(comptime T: type, comptime config: TypedPoolConfig) type {
    return struct {
        const default_page_size = 2048;

        const PoolSlotType = if (@sizeOf(T) > @sizeOf(FreeNode))
            T
        else
            FreeNode;

        const Pool = @This();
        const elem_size = @sizeOf(PoolSlotType);
        const alignment = @alignOf(PoolSlotType);

        const handles_padding: usize = @sizeOf(PageHeader) % @alignOf(Handle);
        const slots_padding: usize = @sizeOf(Handle) % @alignOf(PoolSlotType);

        const PageHeader = PageTableList.Node;

        // give 0 shits about anything but the next freee node
        const FreeSpaceList = std.SinglyLinkedList(struct {});

        const FreeNode = FreeSpaceList.Node;

        /// pages additionally give some shits about alignment
        const PageTableList = std.SinglyLinkedList(struct {
            const Header = @This();
            cap: usize,
            count: usize,

            pub fn handles(self: *Header) []Handle {
                const base_address: usize = std.mem.Alignment.forward(
                    std.mem.Alignment.fromByteUnits(@alignOf(PageHeader)),
                    @intFromPtr(self) + @sizeOf(PageHeader),
                );

                const ptr = @as([*]Handle, @ptrFromInt(base_address));
                return ptr[0..self.count];
            }

            pub fn slots(self: *Header) []FreeNode {
                // Implemented the lazy way, who gives a shit
                const base_handle_addr = std.mem.Alignment.forward(
                    std.mem.Alignment.fromByteUnits(alignment),
                    @intFromPtr(self.handles().ptr),
                );

                const ptr = @as([*]FreeNode, @ptrFromInt(base_handle_addr));

                return ptr[0..self.count];
            }
        });
        pub const Handle = common.Handle(T, .{
            .generation_bits = config.generation_bits,
            .index_bits = config.index_bits,
        });

        free_list: FreeSpaceList,
        page_list: PageTableList,
        allocator: Allocator,

        pub fn initPreheated(allocator: Allocator, count: usize) PoolError!Pool {
            var new_pool = try Pool.init(allocator);
            errdefer new_pool.deinit();

            try new_pool.forceGrowPage(@max(count, @min(count * 2, std.math.maxInt(u16))));
            try new_pool.preheat(count);
            return new_pool;
        }

        pub fn newFreeNode(self: *Pool) PoolError!*FreeNode {
            var page_node = self.page_list.first orelse
                try self.growPage(default_page_size);

            if (page_node.data.cap == 0) {
                page_node = try self.growPage(default_page_size);
            }

            const new_node = page_node.data.slots()[page_node.data.cap - 1];
            page_node.data.cap -= 1;

            return new_node;
        }

        /// Returns OutOfMemory if Not enough page space is allocated
        pub fn preheat(self: *Pool, count: usize) PoolError!void {
            for (0..count) |_| {
                self.free_list.prepend(try self.newFreeNode());
            }
        }

        /// This distinction exists for the purposes of an initial pool allocation
        fn forceGrowPage(self: *Pool, object_count: usize) PoolError!*PageHeader {
            // This probably needs to include alignment padding bytes for the underlying type
            const size_bytes = object_count * elem_size +
                @sizeOf(PageHeader) + handles_padding + slots_padding;

            const new_block = try self.allocator.alignedAlloc(
                u8,
                @alignOf(PageHeader),
                size_bytes,
            );

            const new_header = @as(*PageHeader, @ptrCast(new_block.ptr));

            // This is for obtaining the starting address from a aligned address.

            new_header.data = object_count;
            self.page_list.prepend(new_header);

            return new_header;
        }

        pub fn growPage(self: *Pool, object_count: usize) PoolError!*PageHeader {
            if (!config.growable) return error.OutOfMemory;

            return self.forceGrowPage(object_count);
        }

        pub fn init(allocator: Allocator) PoolError!Pool {
            return Pool{
                .free_list = .{},
                .page_list = .{},
                .allocator = allocator,
            };
        }

        pub fn reserve(self: *Pool) PoolError!Handle {
        }

        pub fn free(self: *Pool, val: Handle) void {
        }

        pub fn reset(self: *Pool) void {}

        pub fn deinit(self: *Pool) void {
            while (self.page_list.popFirst()) |page| {
                self.allocator.free(page);
            }
        }
    };
}

// Testing goes here:
// We're probably gonna need a lot of them lol.

const TestingStructA = struct {
    items: [10]u32,
};
const TestingPool = TypedPool(TestingStructA);

const testing = std.testing;

// Pool allocation tests
test "pool alloc" {
    var pool = try TestingPool.initPreheated(std.heap.page_allocator, 1024);
    defer pool.deinit();

    for (0..512) |_| {
        _ = try pool.reserve();
    }

    _ = try pool.reserveRange(512);
}

test "pool free" {
    //TODO: Testing partial frees

    // free everything
    var pool = try TestingPool.initPreheated(std.heap.page_allocator, 1024);
    _ = try pool.reserveRange(240);

    pool.freeAll();
    if (pool.inner.free_space.free_nodes.first) |f| {
        try testing.expect(f.data.elem_count == 1024);
        try testing.expect(f.next == null);
    } else return error.InvalidFreeList;
}

const Small = struct {
    a: u8 = 0,
    b: u8 = 0,
    c: u8 = 0,
};

test "out of memory" {
    var pool = try TestingPool.initPreheated(std.heap.page_allocator, 1024);
    defer pool.deinit();

    _ = try pool.reserveRange(120);
}

test "pool with small object" {
    var pool = try TypedPool(Small).initPreheated(std.heap.page_allocator, 1024);
    defer pool.deinit();
    _ = try pool.reserveRange(1);

    pool.freeAll();
    if (pool.inner.free_space.free_nodes.first) |f| {
        try testing.expect(f.data.elem_count == 1024);
        try testing.expect(f.next == null);
    } else return error.InvalidFreeList;
}
