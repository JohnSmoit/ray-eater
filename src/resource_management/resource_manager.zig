const std = @import("std");
const Self = @This();

const common = @import("common");
const Registry = @import("registry.zig");

const Allocator = std.mem.Allocator;

const TypeId = common.TypeId;

const Handle = common.Handle;
const OpaqueHandle = common.OpaqueHandle;
const Predicate = Registry.Predicate;

pub const Config = struct {
    allocator: Allocator,
    pool_sizes: usize,
};

fn PoolHandle(comptime T: type) type {
    return common.ObjectPool(T, .{}).ReifiedHandle;
}

// pools: MemoryPoolsTable,

pub fn init(config: Config, registry: *Registry) !Self {
    _ = config;
    _ = registry;

    return undefined;
    // loop through each API registry entry
    // and initialize the table with a pool for each entry
    // whose management strategy is tagged as "Pooled"
   // var entries_iter = registry.select();
   // var entries = entries_iter
   //     .where(Predicate.ManagementModeIs(.Pooled))
   //     .iterator();

   // var table = MemoryPoolsTable.init(config.allocator);

   // while (entries.next()) |entry| {
   //     const pool_config = PoolAllocator.Config{
   //         .elem_size = entry.size_bytes,
   //         .elem_count = config.pool_sizes,
   //     };

   //     try table.put(
   //         entry.type_id,
   //         try PoolAllocator.initAlloc(config.allocator, pool_config),
   //     );
   // }

   // return Self{
   //     .pools = table,
   // };
}

pub fn createTransient(self: *Self, comptime APIType: type) !*APIType {
    _ = self;

    return undefined;
}

pub fn reservePooledByType(self: *Self, comptime APIType: type) !PoolHandle(APIType) {
    _ = self;

    return PoolHandle(APIType).init(undefined, undefined);
}

