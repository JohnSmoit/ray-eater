const std = @import("std");
const vk = @import("vulkan");
const api = @import("vulkan.zig");

const Allocator = std.mem.Allocator;
const Image = @import("image.zig");
const Device = api.Device;

const Self = @This();

img: Image = undefined,
view: Image.View = undefined,

h_sampler: vk.Sampler = .null_handle,

dev: *const Device = undefined,

fn initSampler(self: *Self) !void {
    const max_aniso = self.dev.props.limits.max_sampler_anisotropy;

    self.h_sampler = try self.dev.pr_dev.createSampler(&.{
        .mag_filter = .linear,
        .min_filter = .linear,

        .address_mode_u = .mirrored_repeat,
        .address_mode_v = .mirrored_repeat,
        .address_mode_w = .mirrored_repeat,

        .anisotropy_enable = vk.TRUE,
        .max_anisotropy = max_aniso,
        
        // If address mode is set to border clamping, this is the color the sampler
        // will return if sampled beyond the image's limits
        .border_color = .int_opaque_black,
        
        // As a shader freak, I generally prefer my sampler coordinates to be normalized :}
        .unnormalized_coordinates = vk.FALSE,

        // Which comparison option to use when sampler filtering occurs
        // (sometimes helpful for shadow mapping apparently)
        .compare_enable = vk.FALSE,
        .compare_op = .always,
        
        // Mipmapping stuff -- TBD
        .mipmap_mode = .linear,
        .mip_lod_bias = 0,
        .min_lod = 0,
        .max_lod = 0,
    }, null);
}

pub fn fromFile(dev: *const Device, filename: []const u8, allocator: Allocator) !Self {
    const image = try Image.fromFile(dev, filename, allocator);
    const view = try image.createView(); 
    var tex = Self{
        .img = image,
        .view = view,
        .dev = dev,
    };

    try tex.initSampler();
    
    return tex;
} 


pub fn deinit(self: *const Self) void {
    self.dev.pr_dev.destroySampler(self.h_sampler, null);

    self.view.deinit();
    self.img.deinit();
}
