const std = @import("std");
const vk = @import("vulkan");
const api = @import("vulkan.zig");

const Image = @import("image.zig");
const ImageView = Image.View;
const Device = api.Device;

const Self = @This();

img: Image,
view: ImageView,
dev: *const Device,

pub fn init(dev: *const Device, dimensions: vk.Extent2D) !Self {
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
