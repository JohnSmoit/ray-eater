const std = @import("std");
const vk = @import("vulkan");
const base = @import("base.zig");
const util = @import("../util.zig");

const Context = @import("../context.zig");
const DeviceHandler = base.DeviceHandler;
const Allocator = std.mem.Allocator;

const CommandBuffer = @import("command_buffer.zig");
const FrameBuffer = @import("frame_buffer.zig");

const Self = @This();

pub const log = std.log.scoped(.renderpass);

pub const AttachmentType = enum {
    Color,
    Depth,
};

pub const ConfigEntry = struct {
    attachment: vk.AttachmentDescription,
    tipo: AttachmentType,
};

pr_dev: *const vk.DeviceProxy,
h_rp: vk.RenderPass,

pub fn initAlloc(
    ctx: *const Context,
    allocator: Allocator,
    attachments: []const ConfigEntry,
) !Self {
    const pr_dev: vk.DeviceProxy = ctx.env(.di);
    var col_refs = try allocator.alloc(vk.AttachmentReference, attachments.len);
    defer allocator.free(col_refs);

    var attachments_list = try allocator.alloc(vk.AttachmentDescription, attachments.len);
    defer allocator.free(attachments_list);

    var depth_ref: ?vk.AttachmentReference = null;

    var col_count: u32 = 0;

    for (attachments, 0..) |e, index| {
        attachments_list[index] = e.attachment;

        switch (e.tipo) {
            .Color => {
                col_refs[col_count] = .{
                    .attachment = @intCast(index),
                    .layout = .color_attachment_optimal,
                };

                col_count += 1;
            },
            .Depth => {
                if (depth_ref != null) {
                    return error.TooManyDepthAttachments;
                }

                depth_ref = .{
                    .attachment = @intCast(index),
                    .layout = .depth_stencil_attachment_optimal,
                };
            },
        }
    }

    const subpass_desc = vk.SubpassDescription{
        .color_attachment_count = col_count,
        .p_color_attachments = col_refs.ptr,

        .p_depth_stencil_attachment = if (depth_ref != null) &depth_ref.? else null,
        .pipeline_bind_point = .graphics,
    };

    const subpass_dep = vk.SubpassDependency{
        .src_subpass = vk.SUBPASS_EXTERNAL,
        .dst_subpass = 0,

        .src_stage_mask = .{
            .color_attachment_output_bit = true,
            .early_fragment_tests_bit = true,
        },
        .src_access_mask = .{},

        .dst_stage_mask = .{
            .color_attachment_output_bit = true,
            .early_fragment_tests_bit = true,
        },
        .dst_access_mask = .{
            .color_attachment_write_bit = true,
            .depth_stencil_attachment_write_bit = true,
        },
    };

    const renderpass = pr_dev.createRenderPass(&.{
        .attachment_count = @intCast(attachments_list.len),
        .p_attachments = attachments_list.ptr,

        .subpass_count = 1,
        .p_subpasses = util.asManyPtr(vk.SubpassDescription, &subpass_desc),

        .dependency_count = 1,
        .p_dependencies = util.asManyPtr(vk.SubpassDependency, &subpass_dep),
    }, null) catch |err| {
        log.err("Failed to create render pass: {!}", .{err});
        return err;
    };

    log.debug("Successfully initialized renderpass", .{});

    return .{
        .pr_dev = &pr_dev,
        .h_rp = renderpass,
    };
}

pub fn deinit(self: *const Self) void {
    self.pr_dev.destroyRenderPass(self.h_rp, null);
    log.debug("Successfully destroyed renderpass", .{});
}

pub fn begin(self: *const Self, cmd_buf: *const CommandBuffer, framebuffers: *const FrameBuffer, image_index: u32) void {
    const current_fb = framebuffers.get(image_index);
    const clear_colors = [2]vk.ClearValue{ .{ .color = .{
        .float_32 = .{ 0, 0, 0, 1.0 },
    } }, .{
        .depth_stencil = .{ .depth = 1.0, .stencil = 0.0 },
    } };

    self.pr_dev.cmdBeginRenderPass(cmd_buf.h_cmd_buffer, &.{
        .render_pass = self.h_rp,
        .framebuffer = current_fb.h_framebuffer,
        .render_area = current_fb.extent,
        .clear_value_count = clear_colors.len,
        .p_clear_values = clear_colors[0..],
    }, .@"inline");
}

pub fn end(self: *const Self, cmd_buf: *const CommandBuffer) void {
    self.pr_dev.cmdEndRenderPass(cmd_buf.h_cmd_buffer);
}
