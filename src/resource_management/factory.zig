//! Creating and destroying API types with a unified context,
//! configuration parameters, and common configurable interfaces.
const std = @import("std");

const Context = @import("../context.zig");
const Registry = @import("registry.zig");

const testing = std.testing;
const common = @import("common");
const cfg = common.config;
const api = @import("../api/api.zig");
const env_api = @import("../env.zig");

const Config = struct {};
const Factory = @This();

const FactoryVariant = enum { Managed, Unmanaged };

const crapi = Registry.ComptimeAPI;

/// Since anything can be created, any sort of static resource
/// could be required from an application instance.
const Env = Context.Environment;

env: Env,

pub fn init(env: Env) Factory {
    return Factory {
        .env = env,
    };
}

fn createInPlace(
    self: *Factory,
    comptime APIType: type,
    inst: *APIType,
    config: crapi.ResolveConfigType(APIType),
) !void {
    const entry_config = crapi.GetRegistry(APIType) orelse
        @compileError("Invalid API type: " ++ @typeName(APIType) ++ " (could not find registry config)");
    const EnvFields = crapi.EnvFor(APIType);
    const ConfigType = entry_config.ConfigType;
    const ErrorType = entry_config.InitErrors;
    const InitFunc = *const fn (
        *APIType,
        EnvFields,
        ConfigType,
    ) ErrorType!void;
    const registry = self.env.get(.registry);

    const reg_entry = registry.getEntry(common.typeId(APIType)) orelse
        return error.InvalidAPIType;

    var populated_env: EnvFields = undefined;

    env_api.populate(&populated_env, self.env);
    // nice and safe.
    const initFn: InitFunc = @ptrCast(@alignCast(reg_entry.initFn));

    try initFn(inst, populated_env, config);
}

fn allocManaged(
    self: *Factory, 
    comptime APIType: type, 
) !std.meta.Tuple(&.{
    *APIType, 
    crapi.ManagedReturnType(APIType)}
) {
    const ProxyType = crapi.ManagedReturnType(APIType);
    const entry_config = crapi.GetRegistry(APIType) orelse 
        @compileError("Invalid registry");

    // unmanaged resource shouldn't be created using managed functions
    std.debug.assert(entry_config.management != .Unmanaged);
    var res = self.env.get(.res);

    var ptr: *APIType = undefined;
    var proxy: ProxyType = undefined;


    switch (entry_config.management) {
        .Transient => {
            ptr = try res.createTransient(APIType);
            proxy = .{.handle = ptr};
        },
        //TODO: Streamed allocations need an actual system
        .Pooled, .Streamed => {
            const handle = 
                try res.reservePooledByType(APIType);

            ptr = handle.getAssumeValid();
            proxy = .{.handle = handle};
        },

        .Unmanaged => unreachable,
    }

    return .{ptr, proxy};
}

/// some management modes return different handle variants or just pointers.
/// This depends on the handle variant of the particular type
pub fn create(
    self: *Factory,
    comptime APIType: type, 
    config: crapi.ResolveConfigType(APIType),
) !crapi.ManagedReturnType(APIType) { 
    const ptr, const h = try self.allocManaged(APIType);
    try self.createInPlace(APIType, ptr, config);

    return h;
}

/// Creates a new API type with a pre-populated configuration value.
/// Since, some vulkan objects can be heavy on parameterization.
pub fn createPreconfig(
    self: *Factory,
    comptime APIType: type, 
    comptime profile: crapi.ResolveConfigRegistry(APIType).Profiles,
    params: anytype,
) !crapi.ManagedReturnType(APIType) {
    const ConfigType = crapi.ResolveConfigType(APIType);
    const config = ConfigType.profile(profile, params);

    return self.create(APIType, config);
}

/// Creates a new object but with a user-provided allocator
pub fn createAllocated(
    self: *Factory,
    comptime APIType: type, 
    allocator: std.mem.Allocator,
    config: crapi.ResolveConfigType(APIType),
) !*APIType {
    const new = try allocator.create(APIType);
    errdefer allocator.destroy(new);

    try self.createInPlace(APIType, new, config);
    return new;
}

pub fn createPreconfigAllocated(
    self: *Factory,
    comptime APIType: type, 
    comptime profile: crapi.ResolveConfigRegistry(APIType).Profiles,
    allocator: std.mem.Allocator,
    params: anytype,
) !*APIType {
    const ConfigType = crapi.ResolveConfigType(APIType);
    const config = ConfigType.profile(profile, params);

    return self.createAllocated(APIType, allocator, config);
}

pub fn createInPlacePreconfig(
    self: *Factory,
    comptime APIType: type, 
    comptime profile: crapi.ResolveConfigRegistry(APIType).Profiles,
    inst: *APIType,
    params: anytype,
) !void {
    const ConfigType = crapi.ResolveConfigType(APIType);
    const config = ConfigType.profile(profile, params);

    try self.createInPlace(APIType, inst, config);
}

const CommandBuffer = api.CommandBuffer.CommandBuffer;

const ray_testing = @import("../root.zig").testing;

test "factory functionality" {

    const test_ctx = try ray_testing.MinimalVulkanContext.initMinimalVulkan(
        testing.allocator, 
        .{.noscreen=true}
    );
    var factory_shit = Factory.init(Env.initRaw(.{}));

    defer test_ctx.deinit(testing.allocator);

    _ = try factory_shit.create(CommandBuffer, .{.one_shot = true});
}
