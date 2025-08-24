const std = @import("std");
const vk = @import("vulkan");
const api = @import("api.zig");
const util = @import("../util.zig");

const DeviceInterface = api.DeviceInterface;
const ShaderModule = api.ShaderModule;
const CommandBuffer = api.CommandBuffer;

const Descriptor = api.Descriptor;
const ResolvedBinding = api.ResolvedDescriptorBinding;

const Allocator = std.mem.Allocator;

const Context = @import("../context.zig");
const Self = @This();

pub const Config = struct {
    shader: *const ShaderModule,
    desc: api.Descriptor,
};

pr_dev: *const DeviceInterface,
h_pipeline: vk.Pipeline,
h_pipeline_layout: vk.PipelineLayout,
desc: Descriptor,

pub fn init(ctx: *const Context, cfg: Config) !Self {
    const pr_dev: *const DeviceInterface = ctx.env(.di);
    // create the actual pipeline
    const layout = try pr_dev.createPipelineLayout(&.{
        .flags = .{},
        .set_layout_count = 1,
        .p_set_layouts = &.{cfg.desc.vkLayout()},
    }, null);
    errdefer pr_dev.destroyPipelineLayout(layout, null);

    var new = Self{
        .pr_dev = pr_dev,
        .desc = cfg.desc,
        .h_pipeline_layout = layout,
        .h_pipeline = .null_handle,
    };

    const compute_pipeline_info = vk.ComputePipelineCreateInfo{
        .base_pipeline_index = 0,
        .layout = layout,
        .stage = cfg.shader.pipeline_info,
    };

    _ = try pr_dev.createComputePipelines(
        .null_handle,
        1,
        &.{compute_pipeline_info},
        null,
        @as([*]vk.Pipeline, @ptrCast(&new.h_pipeline)),
    );

    return new;
}

pub fn updateData(self: *Self, binding: u32, data: anytype) !void {
    self.desc.setValue(binding, data);
}

pub fn bind(self: *const Self, cmd_buf: *const CommandBuffer) void {
    self.pr_dev.cmdBindPipeline(cmd_buf.h_cmd_buffer, .compute, self.h_pipeline);
    self.desc.use(cmd_buf, self.h_pipeline_layout, .{ .bind_point = .compute });
}

pub fn dispatch(
    self: *const Self,
    cmd_buf: *const CommandBuffer,
    group_x: u32,
    group_y: u32,
    group_z: u32,
) void {
    self.pr_dev.cmdDispatch(
        cmd_buf.h_cmd_buffer,
        group_x,
        group_y,
        group_z,
    );
}

pub fn deinit(self: *Self) void {
    self.pr_dev.destroyPipeline(self.h_pipeline, null);
    self.pr_dev.destroyPipelineLayout(self.h_pipeline_layout, null);

    self.desc.deinit();
}
