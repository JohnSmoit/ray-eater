const std = @import("std");
const vk = @import("vulkan");
const api = @import("api.zig");

const DeviceInterface = api.DeviceInterface;
const ShaderModule = api.ShaderModule;

const Allocator = std.mem.Allocator;

const Context = @import("../context.zig");
const Self = @This();

pub const Config = struct {
    shader: *const ShaderModule,
};

pr_dev: *const DeviceInterface,

pub fn fromShaderFileAlloc(ctx: *const Context, path: []const u8, allocator: Allocator) !Self {
    const shader = try ShaderModule.fromSourceFile(ctx, allocator, .{
        .filename = path,
        .stage = .Compute,
    });
    defer shader.deinit();

    return init(ctx, .{
        .shader = shader,
    });
}

pub fn init(ctx: *const Context, cfg: Config) !Self {
    const pr_dev: *const DeviceInterface = ctx.env(.di);

    // make some descriptors for the pipeline's memory layout
    // create the actual pipeline
}
