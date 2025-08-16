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
const common = @import("../common/common.zig");
const assert = std.debug.assert;

const Allocator = std.mem.Allocator;
const AnyPtr = common.AnyPtr;

const Self = @This();

/// Free space LInked list
/// Mostly just a std.LinkedList of allocation headers
/// but does some extra stuff to have the nodes stored in-place
/// with the actual memory pool.
const FreeSpaceList = struct {
    const BlockHeader = struct {
        elem_count: usize,
    };

    const BlockList = std.DoublyLinkedList(BlockHeader);
    const ListNode = BlockList.Node;

    elem_size: usize,
    free_nodes: BlockList,
    buf: []u8,

    fn makeNode(buf: []u8, header: BlockHeader) *ListNode {
        assert(buf.len > @sizeOf(ListNode));
        const node = @as(*ListNode, @ptrCast(@alignCast(buf.ptr)));

        node.data = header;
        return node;
    }

    // possibly use a free-list styled allocator to do this
    fn coalesce(self: *FreeSpaceList, root: *ListNode) void {
        _ = self;
        _ = root;
    }

    // This function does not work at all lol
    pub fn pop(self: *FreeSpaceList, count: usize) ?*anyopaque {
        var node: ?*ListNode = self.free_nodes.popFirst() orelse return null;

        while (node != null and node.?.data.elem_count < count) : (node = node.?.next) {}

        const n = node orelse return null;

        if (n.data.elem_count > count) {
            const bytes_size = count * self.elem_size;
            const new_node: *ListNode = @ptrFromInt(@intFromPtr(n) + bytes_size);

            new_node.* = .{ .data = .{
                .elem_count = n.data.elem_count - count,
            } };

            self.free_nodes.prepend(new_node);
        }

        return n;
    }

    pub fn free(self: *FreeSpaceList, ptr: *anyopaque) void {
        //TODO: This needs some work
        //Can't use a linked list to effectively handle multiple item frees, even with a count
        //Mostly because of the coalesce routine (it would need to be an RB tree of sorts)

        _ = self;
        _ = ptr;
    }

    pub fn init(buf: []u8, elem_size: usize) FreeSpaceList {
        const num_elements = @divExact(buf.len, elem_size);
        const node = makeNode(buf, .{ .elem_count = num_elements });

        var list = BlockList{};
        list.prepend(node);

        return FreeSpaceList{
            .elem_size = elem_size,
            .free_nodes = list,
            .buf = buf,
        };
    }
};

/// Type Safe generic pool wrapper
pub fn TypedPool(comptime T: type) type {
    return struct {
        const Pool = @This();
        const elem_size = @sizeOf(T);
        const type_id = common.typeId(T);
        inner: Self,

        pub fn initAlloc(allocator: Allocator, count: usize) !Pool {
            const pool_config = Config{
                .elem_size = elem_size,
                .elem_count = count,
            };

            return Pool{
                .inner = try Self.initAlloc(allocator, pool_config),
            };
        }

        pub fn init(buf: []T, count: usize) Pool {
            const bytes_len = buf.len * elem_size;
            const buffer = @as([*]u8, @ptrCast(@alignCast(buf.ptr)))[0..bytes_len];

            const pool_config = Config{
                .elem_size = elem_size,
                .elem_count = count,
            };

            return Pool.init(buffer, pool_config);
        }

        pub fn reserve(self: *Pool) PoolErrors!*T {
            return @as(*T, @ptrCast(@alignCast(try self.inner.reserve())));
        }

        pub fn reserveRange(self: *Pool, count: usize) PoolErrors![]T {
            return @as([*]T, @ptrCast(
                @alignCast(try self.inner.reserveRange(count)),
            ))[0..count];
        }

        pub fn freeAll(self: *Pool) void {
            self.inner.freeAll();
        }

        pub fn deinit(self: *Pool) void {
            self.inner.deinit();
        }
    };
}

// Limited to u32 boundaries, just used usize since int casting is annoying
pub const Config = struct {
    elem_size: usize,
    elem_count: usize,
};

pub const PoolErrors = error{
    OutOfMemory,
};

config: Config,

// raw backing buffer, very rarely directly access this...
buf: []u8,
free_space: FreeSpaceList,

allocator: ?Allocator = null,

pub fn initAlloc(allocator: Allocator, config: Config) !Self {
    const total_size = config.elem_count * config.elem_size;
    const buf = try allocator.alloc(u8, total_size);

    var new = init(buf, config);
    new.allocator = allocator;

    return new;
}

/// Reserve a single item
/// Pointer is guarunteed to refer to a block
/// of memory for the correct size.
pub fn reserve(self: *Self) PoolErrors!*anyopaque {
    return self.free_space.pop(1) orelse PoolErrors.OutOfMemory;
}

/// Reserve multiple items contiguously
pub fn reserveRange(self: *Self, count: usize) PoolErrors!*anyopaque {
    return self.free_space.pop(count) orelse return PoolErrors.OutOfMemory;
}

/// free a previous allocation
/// I'll do this later once pool items are more likely to be reused
pub fn free(self: *Self, item: *anyopaque) void {
    _ = self;
    _ = item;
}

pub fn freeAll(self: *Self) void {
    // Just overwrite the existing free space list with a new one, which will cover the entire pool
    // no leakage issues since the list is stored in-place
    self.free_space = FreeSpaceList.init(self.buf, self.config.elem_size);
}

/// ## Notes:
/// * Directly passed buffer must respect alginment requirements
///   of the state type
pub fn init(buf: []u8, config: Config) Self {
    return .{
        .config = config,

        .buf = buf,
        .free_space = FreeSpaceList.init(buf, config.elem_size),
    };
}

pub fn deinit(self: *Self) void {
    if (self.allocator) |allocator| {
        allocator.free(self.buf);
    }
}

// Testing goes here:
// We're probably gonna need a lot of them lol.


const TestingStructA = struct {
    items: [6]u32,
};
const TestingPool = TypedPool(TestingStructA);

const testing = std.testing;

// Pool allocation tests
test "pool alloc" {
    var pool = try TestingPool.initAlloc(std.heap.page_allocator, 1024);
    defer pool.deinit();

    for (0..512) |_| {
        _ = try pool.reserve();
    }

    _ = try pool.reserveRange(512);
}

test "pool free" {
    //TODO: Testing partial frees
    
    // free everything
    var pool = try TestingPool.initAlloc(std.heap.page_allocator, 1024);
    _ = try pool.reserveRange(240);

    pool.freeAll();
    if (pool.inner.free_space.free_nodes.first) |f| {
        try testing.expect(f.data.elem_count == 1024);
        try testing.expect(f.next == null);
    } else return error.InvalidFreeList;
}

test "out of memory" {
    var pool = try TestingPool.initAlloc(std.heap.page_allocator, 1024);
    defer pool.deinit();

    _ = try pool.reserveRange(120);
    try testing.expectError(PoolErrors.OutOfMemory, pool.reserveRange(905));
}
