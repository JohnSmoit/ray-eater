const std = @import("std");
const vk = @import("vulkan");

const Allocator = std.mem.Allocator;
const RenderPass = @import("renderpass.zig");
const Swapchain = @import("swapchain.zig");
const Context = @import("../context.zig");

const Self = @This();

// TODO: Maybe some helpers for resolving swapchain frame target?
pub const FrameBufferInfo = struct {
    h_framebuffer: vk.Framebuffer,
    extent: vk.Rect2D,
};
pub const Config = struct {
    renderpass: *const RenderPass,
    image_views: []const Swapchain.ImageInfo,
    depth_view: ?vk.ImageView = null,
    extent: vk.Rect2D,
};

framebuffers: []vk.Framebuffer,
pr_dev: *const vk.DeviceProxy,
allocator: Allocator,
extent: vk.Rect2D,

/// ## Notes
/// Unfortunately, allocation is neccesary due to the runtime count of the swapchain
/// images
pub fn initAlloc(ctx: *const Context, allocator: Allocator, config: *const Config) !Self {
    const pr_dev: *const vk.DeviceProxy = ctx.env(.di);
    var framebuffers = try allocator.alloc(vk.Framebuffer, config.image_views.len);

    const attachment_count: u32 = if (config.depth_view != null) 2 else 1;

    for (config.image_views, 0..) |*info, index| {
        const views = [2]vk.ImageView{ info.h_view, config.depth_view orelse .null_handle };

        framebuffers[index] = try pr_dev.createFramebuffer(&.{
            .render_pass = config.renderpass.h_rp,
            .attachment_count = attachment_count,
            .p_attachments = views[0..],
            .width = config.extent.extent.width,
            .height = config.extent.extent.height,
            .layers = 1,
        }, null);
    }

    return .{
        .framebuffers = framebuffers,
        .pr_dev = pr_dev,
        .allocator = allocator,
        .extent = config.extent,
    };
}

pub fn get(self: *const Self, image_index: u32) FrameBufferInfo {
    return FrameBufferInfo{
        .h_framebuffer = self.framebuffers[@intCast(image_index)],
        .extent = self.extent,
    };
}

pub fn deinit(self: *const Self) void {
    for (self.framebuffers) |fb| {
        self.pr_dev.destroyFramebuffer(fb, null);
    }

    self.allocator.free(self.framebuffers);
}
