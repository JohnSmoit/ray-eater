const std = @import("std");
const Self = @This();

const common = @import("common.zig");
const Registry = @import("registry.zig");
const h = @import("handle.zig");

const PoolAllocator = @import("pool_allocator.zig");
const Allocator = std.mem.Allocator;

const TypeId = common.TypeId;
const MemoryPoolsTable = std.AutoHashMap(TypeId, PoolAllocator);

const Handle = h.Handle;
const OpaqueHandle = h.OpaqueHandle;
const Predicate = Registry.Predicate;

pub const Config = struct {
    allocator: Allocator,
    pool_sizes: usize,
};

pools: MemoryPoolsTable,

pub fn init(config: Config, registry: Registry) !Self {
    // loop through each API registry entry 
    // and initialize the table with a pool for each entry
    // whose management strategy is tagged as "Pooled"
    
    const entries = registry.select()
        .where(Predicate.ManagementModeIs(.Pooled))
    .iterator();

    var table = MemoryPoolsTable.init(config.allocator);

    while (entries.next()) |entry| {
        std.debug.print("Creating pool for type {s}\n", .{entry.type_name});
        const pool_config = PoolAllocator.Config{
            .elem_size = entry.size_bytes,
            .elem_count = config.pool_sizes,
        };

        try table.put(entry.id, 
            try PoolAllocator.initAlloc(config.allocator, pool_config),
        );
    }

    return Self{
        .pools = table,
    };
}
