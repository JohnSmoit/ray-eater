const std = @import("std");
const vk = @import("vulkan");

const Image = @import("image.zig");
const ImageView = Image.View;
const DeviceHandler = @import("base.zig").DeviceHandler;

const Self = @This();

const log = std.log.scoped(.depth_buffer);

img: Image,
view: ImageView,
dev: *const DeviceHandler,

pub fn init(dev: *const DeviceHandler, dimensions: vk.Extent2D) !Self {
    log.debug("Chosen depth format: {s}", .{@tagName(try dev.findDepthFormat())});
    const image = try Image.init(dev, &.{
        .format = try dev.findDepthFormat(),
        .height = dimensions.height,
        .width = dimensions.width,

        .mem_flags = .{ .device_local_bit = true },
        .tiling = .optimal,
        .usage = .{ .depth_stencil_attachment_bit = true },
        .initial_layout = .undefined,
    });
    errdefer image.deinit();

    const view = try image.createView(.{ .depth_bit = true });

    return Self{
        .view = view,
        .img = image,
        .dev = dev,
    };
}


pub fn deinit(self: *const Self) void {
    self.view.deinit();
    self.img.deinit();
}
