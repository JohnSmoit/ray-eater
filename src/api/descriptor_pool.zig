//! This is more of a manager for descriptor pools then
//! an singular descriptor pool.
//!
//! The idea here is to have descriptors specify so called "usage hints"
//! which are meant to describe how the descriptor will be used.
//! These hints will encompass either the lifetime of the descriptor set and/or
//! the actual makeup of descriptors.

const common = @import("common_types.zig");
const vk = @import("vulkan");
const std = @import("std");
const api = @import("api.zig");

const Allocator = std.mem.Allocator;

const UsageInfo = common.DescriptorUsageInfo;
const PoolUsageMap = std.EnumMap(UsageInfo.LifetimeScope, AnyPool);
const Context = @import("../context.zig");

const log = std.log.scoped(.desc_pool);

const PoolErrors = error{
    /// Pool has run out of memory
    OutOfMemory,
    /// an internal vulkan error has occured
    /// (best check validation logs on a debug build)
    Internal,
};

const AnyPool = struct {
    pub const VTable = struct {
        rawReserve: *const fn (
            *anyopaque,
            /// This mostly exists for the purpose of potentially having more sophisticated pool managment
            /// within a single usage pool
            []const UsageInfo,
            []const vk.DescriptorSetLayout,
            /// Descriptor sets are written into this user provided slice rather than allocation
            []vk.DescriptorSet,
        ) PoolErrors!void,
        rawFree: *const fn (
            *anyopaque,
            []const UsageInfo,
            []const vk.DescriptorSet,
        ) void,

        reset: *const fn (
            *anyopaque,
        ) void,
    };

    vtable: *const VTable,
    ctx: *anyopaque,

    pub fn rawReserve(
        self: AnyPool,
        usages: []const UsageInfo,
        layouts: []const vk.DescriptorSetLayout,
        sets: []vk.DescriptorSet,
    ) PoolErrors!void {
        try self.vtable.rawReserve(self.ctx, usages, layouts, sets);
    }

    pub fn rawFree(
        self: AnyPool,
        usages: []const UsageInfo,
        layouts: []const vk.DescriptorSet,
    ) void {
        return self.vtable.rawFree(self.ctx, usages, layouts);
    }

    pub fn reset(
        self: AnyPool,
    ) void {
        return self.vtable.reset(self.ctx);
    }
};

const DescriptorSizeRatios = std.EnumMap(common.DescriptorType, f32);

const DescriptorType = common.DescriptorType;
const PoolArena = struct {
    const ratios = DescriptorSizeRatios.init(.{
        .Uniform = 1.0,
        .Sampler = 2.0,
        .StorageBuffer = 0.5,
        .Image = 1.0,
    });

    inline fn calcDescriptorCount(t: DescriptorType, size: usize) u32 {
        const ratio = ratios.get(t) orelse unreachable;
        return @intFromFloat(ratio * @as(f32, @floatFromInt(size)));
    }
    fn poolSizesForCount(set_count: usize) [4]vk.DescriptorPoolSize {
        return [_]vk.DescriptorPoolSize{
            .{
                .type = DescriptorType.Uniform.toVkDescriptor(),
                .descriptor_count = calcDescriptorCount(.Uniform, set_count),
            },
            .{
                .type = DescriptorType.Sampler.toVkDescriptor(),
                .descriptor_count = calcDescriptorCount(.Sampler, set_count),
            },
            .{
                .type = DescriptorType.Image.toVkDescriptor(),
                .descriptor_count = calcDescriptorCount(.Image, set_count),
            },
            .{
                .type = DescriptorType.StorageBuffer.toVkDescriptor(),
                .descriptor_count = calcDescriptorCount(.StorageBuffer, set_count),
            },
        };
    }

    h_desc_pool: vk.DescriptorPool,
    di: api.DeviceInterface,

    pub fn init(di: api.DeviceInterface, size: usize) !PoolArena {
        const pool_sizes = poolSizesForCount(size);

        const pool_create_info = vk.DescriptorPoolCreateInfo{
            .max_sets = @intCast(size),
            .p_pool_sizes = &pool_sizes,
            .pool_size_count = pool_sizes.len,
        };

        const desc_pool = try di.createDescriptorPool(
            &pool_create_info,
            null,
        );

        return PoolArena{
            .h_desc_pool = desc_pool,
            .di = di,
        };
    }

    fn rawReserve(
        ctx: *anyopaque,
        usages: []const UsageInfo,
        layouts: []const vk.DescriptorSetLayout,
        /// Caller provides the memory for the sets (tries to allocate a set for all elements of slice)
        sets: []vk.DescriptorSet,
    ) PoolErrors!void {
        const self = @as(*PoolArena, @ptrCast(@alignCast(ctx)));

        const alloc_info = vk.DescriptorSetAllocateInfo{
            .descriptor_pool = self.h_desc_pool,
            .descriptor_set_count = @intCast(sets.len),
            .p_set_layouts = layouts.ptr,
        };

        self.di.allocateDescriptorSets(&alloc_info, sets.ptr) catch |e| {
            return switch (e) {
                error.OutOfHostMemory, error.OutOfDeviceMemory, error.OutOfPoolMemory => PoolErrors.OutOfMemory,
                error.FragmentedPool => blk: {
                    // TODO: possibly trigger a defragging routine here
                    log.debug(
                        "pool is too fragmented to allocate.",
                        .{},
                    );
                    break :blk PoolErrors.OutOfMemory;
                },
                else => PoolErrors.Internal,
            };
        };

        _ = usages;
    }

    fn rawFree(
        ctx: *anyopaque,
        usages: []const UsageInfo,
        sets: []const vk.DescriptorSet,
    ) void {
        // Freeing single sets is not allowed without a flag
        // and is thus a no-op for this implementation
        _ = ctx;
        _ = usages;
        _ = sets;
    }

    fn reset(
        ctx: *anyopaque,
    ) void {
        const self = @as(*PoolArena, @ptrCast(@alignCast(ctx)));
        self.di.resetDescriptorPool(self.h_desc_pool, .{}) catch
            @panic("internal descriptor pool error occured");
    }

    pub fn interface(self: *PoolArena) AnyPool {
        return AnyPool{
            .ctx = self,
            .vtable = &AnyPool.VTable{
                .rawFree = rawFree,
                .rawReserve = rawReserve,
                .reset = reset,
            },
        };
    }

    pub fn deinit(self: *PoolArena) void {
        self.di.destroyDescriptorPool(self.h_desc_pool, null);
    }
};

/// for now, I think it is permissible to
/// have the static pool be managed the
/// same as the transient pool via a PoolArena
/// (it just gets freed at the end)
// const StaticPool = struct {
//     h_desc_pool: vk.DescriptorPool,
// };

pools_by_usage: PoolUsageMap,

transient_pool: PoolArena,
//lol
scene_pool: PoolArena,
static_pool: PoolArena,

const Self = @This();
pub const Env = Context.Environment.EnvSubset(.{.di});

pub const PoolSizes = struct {
    transient: usize,
    scene: usize,
    static: usize,
};

//keeps the door open for a more complicated descriptor managment
fn poolByUsage(self: *Self, usage: UsageInfo) AnyPool {
    return self.pools_by_usage.get(usage.lifetime_bits) orelse unreachable;
}

pub fn initSelf(self: *Self, env: Env, sizes: PoolSizes) !void {
    const di: api.DeviceInterface = env.di;

    self.transient_pool = try PoolArena.init(di, sizes.transient);
    errdefer self.transient_pool.deinit();

    self.scene_pool = try PoolArena.init(di, sizes.scene);
    errdefer self.scene_pool.deinit();

    self.static_pool = try PoolArena.init(di, sizes.static);
    errdefer self.static_pool.deinit();

    self.pools_by_usage = PoolUsageMap.init(.{
        .Transient = self.transient_pool.interface(),
        .Scene = self.scene_pool.interface(),
        .Static = self.static_pool.interface(),
    });
}

pub fn resetTransient(self: *Self) void {
    self.transient_pool.interface().reset();
}

pub fn reserve(
    self: *Self,
    usage: UsageInfo,
    layout: vk.DescriptorSetLayout,
) !vk.DescriptorSet {
    const pool = self.poolByUsage(usage);
    var set = [1]vk.DescriptorSet{undefined};
    try pool.rawReserve(&.{usage}, &.{layout}, set[0..]);

    return set[0];
}

pub fn reserveRange(
    self: *Self,
    usage: UsageInfo,
    layouts: []const vk.DescriptorSetLayout,
    sets: []vk.DescriptorSet,
) !void {
    const pool = self.poolByUsage(usage);
    try pool.rawReserve( &.{usage}, layouts, sets);
}

pub fn free(
    self: *Self,
    // free does something different depending on the usage
    usage: UsageInfo,
    set: vk.DescriptorSet,
) void {
    self.freeRange(&.{usage}, &.{set});
}

pub fn freeRange(
    self: *Self,
    usages: []const UsageInfo,
    sets: []const vk.DescriptorSet,
) void {
    for (usages, sets) |u, s| {
        const pool = self.poolByUsage(u);
        pool.rawFree(&.{u}, &.{s});
    }
}

pub fn deinit(self: *Self) void {
    self.scene_pool.deinit();
    self.static_pool.deinit();
    self.transient_pool.deinit();
}

