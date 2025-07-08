const std = @import("std");
const api = @import("api.zig");

const e = @import("env.zig");

const Device = api.Device;
const Instance = api.Instance;

const GlobalInterface = api.GlobalInterface;
const InstanceInterface = api.InstanceInterface;
const DeviceInterface = api.DeviceInterface;

const Ref = e.Ref;
const ContextEnv = struct {
    inst: Ref(Instance, .{}),
    dev: Ref(Device, .{}),

    gi: Ref(GlobalInterface, .{}),
    ii: Ref(InstanceInterface, .{}),
    di: Ref(DeviceInterface, .{}),
};
const Environment = e.For(ContextEnv);

const Self = @This();

ctx_env: Environment,

fn ResolveEnvType(comptime field: anytype) type {
    return switch (@TypeOf(field)) {
        void => *const Environment,

        else => blk: {
            const as_enum = @as(Environment.ContextEnum, field);
            break :blk Environment.ResolveInner(as_enum);
        },
    };
}

/// Field must either be a valid enum member for the 
/// generated Context Environment type or void (i.e ".{}").
/// - Specifying an enum member will retrieve the appropriate field from the environment
///   (example: ctx.env(.device) will return env.dev)
/// - Specifying void will return a const * to the entire context
///   (useful if you want to get a scoped context for a device for example)
pub fn env(self: *const Self, comptime field: anytype) ResolveEnvType(field) {
    const Res = ResolveEnvType(field);

    return switch (Res) {
        *const Environment => &self.ctx_env,
        else => @panic("TODO: Properly initialze the environment"), 
    };
}

pub fn init() Self {
    return .{
        .ctx_env = undefined,
    };
}
