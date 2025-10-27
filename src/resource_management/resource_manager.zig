const std = @import("std");
const Self = @This();

const common = @import("common");
const res_api = @import("res.zig");
const Registry = @import("registry.zig");

const Allocator = std.mem.Allocator;

const TypeId = common.TypeId;

const Handle = common.Handle;
const OpaqueHandle = common.OpaqueHandle;
const Predicate = Registry.Predicate;
const crapi = Registry.ComptimeAPI;

const MemoryPoolsTable = struct {
    const PoolTypeMap = std.AutoArrayHashMapUnmanaged(common.TypeId, *anyopaque);

    cfg: Config,
    ///NOTE: If it turns out the type id hack I used produces consecutive values,
    ///this can be replaced with a sparse index
    pool_ptrs: PoolTypeMap,
    pool_arena: std.heap.ArenaAllocator,

    // the actual pools themselves are lazily initialized
    pub fn init(cfg: Config, iter: Registry.Query.Iterator) !MemoryPoolsTable {
        const count = iter.getCount();

        var pool_map = try PoolTypeMap.init(cfg.allocator, &.{}, &.{});
        errdefer pool_map.deinit(cfg.allocator);
        try pool_map.ensureUnusedCapacity(cfg.allocator, count);

        return MemoryPoolsTable{
            .cfg = cfg,
            .pool_ptrs = pool_map,
            .pool_arena = std.heap.ArenaAllocator.init(cfg.allocator),
        };
    }

    /// null if API type is invalid, and panics on allocation failure since there isn't
    /// much to be done recovery wise
    pub fn getPool(table: *MemoryPoolsTable, comptime T: type) ?*res_api.StandardObjectPool(T) {
        if (crapi.GetRegistry(T) == null) return null;

        const type_id = common.typeId(T);
        std.debug.print("Did we survice?\n", .{});
        _ = table.pool_ptrs.count();
        std.debug.print("... Yup\n", .{});
        const pool = table.pool_ptrs.getOrPutAssumeCapacity(
            type_id,
        );

        if (pool.found_existing) {
            return @as(*res_api.StandardObjectPool(T), @ptrCast(@alignCast(pool.value_ptr.*)));
        } else {
            const new_pool = table.cfg.allocator.create(
                res_api.StandardObjectPool(T),
            ) catch @panic("Allocation failed (NOTE: check fixed buffer sizes/ratios)");
            new_pool.* = res_api.StandardObjectPool(T).initPreheated(
                table.pool_arena.allocator(),
                table.cfg.pool_sizes,
            ) catch @panic("Pool initialization failed due to memory exhaustion (NOTE: check fixed buffer sizes/ratios)");

            pool.value_ptr.* = new_pool;

            return new_pool;
        }
    }

    pub fn deinit(table: *MemoryPoolsTable) void {
        // HACK: THis only works because all the memory is controlled by a linear arena allocator
        // But we might want a better strategy
        var iter = table.pool_ptrs.iterator();
        while (iter.next()) |i| {
            if (i.value_ptr.*) |v| {
                table.cfg.allocator.free(v);
            }
        }
        table.pool_ptrs.deinit(table.cfg.allocator);
        table.pool_arena.deinit();
    }
};

const HandleArena = struct {};

pub const Config = struct {
    allocator: Allocator,
    pool_sizes: usize,
};

fn PoolHandle(comptime T: type) type {
    return res_api.StandardObjectPool(T).ReifiedHandle;
}

pools: MemoryPoolsTable,
transients: HandleArena,

pub fn init(config: Config, registry: *Registry) !Self {

    // loop through each API registry entry
    // and initialize the table with a pool for each entry
    // whose (default) management strategy is tagged as "Pooled"
    var q_entries = registry.select();
    const entries_iter = q_entries
        .where(Predicate.ManagementModeIs(.Pooled))
        .iterator();

    const table = try MemoryPoolsTable.init(config, entries_iter);

    return Self{
        .pools = table,
        .transients = undefined,
    };
}

pub fn deinit(res: *Self) void {
    res.pools.deinit();
}

pub fn reserveTransient(res: *Self, comptime T: type) !*T {
    _ = res;
    @panic("reserveTransient: needs implementation");
}

pub fn reservePooledByType(res: *Self, comptime T: type) !PoolHandle(T) {
    if (crapi.GetRegistry(T) == null) @compileError("Invalid type: " ++ @typeName(T) ++ " (missing registry)");
    const pool = res.pools.getPool(T) orelse unreachable;

    return pool.reserveReified();
}
