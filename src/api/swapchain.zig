const std = @import("std");
const vk = @import("vulkan");
const util = @import("common").util;
const base = @import("base.zig");

const Context = @import("../context.zig");
const DeviceHandler = base.DeviceHandler;
const SurfaceHandler = base.SurfaceHandler;

const Allocator = std.mem.Allocator;

const Self = @This();

pub const log = std.log.scoped(.swapchain);

pub const Config = struct {
    requested_format: struct { //TODO: support picking default/picking from multiple
        color_space: vk.ColorSpaceKHR,
        format: vk.Format,
    },
    requested_present_mode: vk.PresentModeKHR,
    requested_extent: vk.Extent2D,
};

pub const ImageInfo = struct {
    h_image: vk.Image,
    h_view: vk.ImageView,
};

surface_format: vk.SurfaceFormatKHR = undefined,
present_mode: vk.PresentModeKHR = undefined,
extent: vk.Extent2D = undefined,
h_swapchain: vk.SwapchainKHR = undefined,
pr_dev: *const vk.DeviceProxy = undefined,
images: []ImageInfo = util.emptySlice(ImageInfo),
allocator: Allocator,
image_index: u32 = 0,

fn chooseSurfaceFormat(
    available: []const vk.SurfaceFormatKHR,
    config: *const Config,
) !vk.SurfaceFormatKHR {
    var chosen_format: ?vk.SurfaceFormatKHR = null;
    for (available) |*fmt| {
        if (fmt.format == config.requested_format.format and
            fmt.color_space == config.requested_format.color_space)
        {
            chosen_format = fmt.*;
            break;
        }
    }

    log.debug("chose surface format: {s}", .{@tagName(chosen_format.?.format)});
    log.debug("Chose color space: {s}", .{@tagName(chosen_format.?.color_space)});

    return chosen_format orelse error.NoSuitableFormat;
}

fn chooseExtent(
    capabilities: *const vk.SurfaceCapabilitiesKHR,
    config: *const Config,
) !vk.Extent2D {
    if (capabilities.current_extent.width != std.math.maxInt(u32)) {
        log.debug("chose natively supported extent", .{});
        return capabilities.current_extent;
    }

    const extent: vk.Extent2D = .{
        .width = std.math.clamp(
            config.requested_extent.width,
            capabilities.min_image_extent.width,
            capabilities.max_image_extent.width,
        ),
        .height = std.math.clamp(
            config.requested_extent.height,
            capabilities.min_image_extent.height,
            capabilities.max_image_extent.height,
        ),
    };

    log.debug("chose extent: [width: {d}, height: {d}]", .{ extent.width, extent.height });
    return extent;
}

fn choosePresentMode(
    available: []const vk.PresentModeKHR,
    config: *const Config,
) vk.PresentModeKHR {
    log.debug("Want present mode: {s}", .{@tagName(config.requested_present_mode)});
    var chosen_mode: ?vk.PresentModeKHR = null;
    for (available) |mode| {
        log.debug("Present mode: {s}", .{@tagName(mode)});
        if (mode == config.requested_present_mode) {
            chosen_mode = mode;

            log.debug("chose present mode: {s}", .{
                @tagName(mode),
            });

            break;
        }
    }

    return chosen_mode orelse fb: {
        log.debug("Chosen fallback present mode: {s}", .{@tagName(.immediate_khr)});
        break :fb .immediate_khr;
    };
}

fn createImageViews(self: *Self) !void {
    const image_handles = try self.pr_dev.getSwapchainImagesAllocKHR(self.h_swapchain, self.allocator);
    defer self.allocator.free(image_handles);

    var images = try self.allocator.alloc(ImageInfo, image_handles.len);

    for (image_handles, 0..) |img, index| {

        // create and assign the corresponding image view
        // this formatting ies zls's fault, plz disable auto format on write since it seems to suck ass
        const image_view = try self.pr_dev.createImageView(&.{ .image = img, .view_type = .@"2d", .format = self.surface_format.format, .components = .{
            .r = .identity,
            .g = .identity,
            .b = .identity,
            .a = .identity,
        }, .subresource_range = .{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        } }, null);

        images[index].h_image = img;
        images[index].h_view = image_view;
    }

    self.images = images;
}

pub fn init(
    ctx: *const Context,
    allocator: Allocator,
    config: Config,
) !Self {
    // The swapchain should NEVER be initialized
    // without surface support, though this implementation
    // is a bit spaghetti
    const device: *const DeviceHandler = ctx.env(.dev);
    const pr_dev: *const vk.DeviceProxy = ctx.env(.di);
    const surface: *const SurfaceHandler = ctx.env(.surf);

    if (device.swapchain_details == null)
        @panic("Cannot initialize swapchain without surface support");

    const details: *const DeviceHandler.SwapchainSupportDetails = &device.swapchain_details.?;

    // request an appropriate number of swapchain images
    var image_count: u32 = details.capabilities.min_image_count + 1;
    if (details.capabilities.max_image_count > 0) {
        image_count = @min(image_count, details.capabilities.max_image_count);
    }

    const surface_format = try chooseSurfaceFormat(
        device.swapchain_details.formats,
        &config,
    );

    const present_mode = choosePresentMode(
        device.swapchain_details.present_modes,
        &config,
    );

    const extent = try chooseExtent(
        &device.swapchain_details.capabilities,
        &config,
    );

    // make sure the swapchain knows about the relationship between our queue families
    // (i.e which families map to which queues or if both map to one and such)
    var queue_indices = [_]u32{
        device.families.graphics_family.?,
        device.families.present_family.?,
    };

    var image_sharing_mode: vk.SharingMode = .exclusive;
    var queue_family_index_count: u32 = 0;
    var p_queue_family_indices: ?[*]u32 = null;
    if (queue_indices[0] != queue_indices[1]) {
        image_sharing_mode = .concurrent;
        queue_family_index_count = queue_indices.len;
        p_queue_family_indices = &queue_indices;
    }

    // specify the gajillion config values to create the swapchain
    var chain = Self{
        .surface_format = surface_format,
        .present_mode = present_mode,
        .extent = extent,
        .pr_dev = pr_dev,
        .allocator = allocator,

        // the giant ass struct for swapchain creation starts here
        .h_swapchain = try device.pr_dev.createSwapchainKHR(&.{
            .surface = surface.h_surface,

            // drop in the queried values
            .min_image_count = image_count,
            .image_format = surface_format.format,
            .image_color_space = surface_format.color_space,
            .present_mode = present_mode,
            .image_extent = extent,

            //hardcoded (for now) values
            .image_array_layers = 1,
            .image_usage = .{ .color_attachment_bit = true },

            // image sharing properties (controls how queues can access and work in tandem)
            // with a given swapchain image
            .image_sharing_mode = image_sharing_mode,
            .queue_family_index_count = queue_family_index_count,
            .p_queue_family_indices = p_queue_family_indices,

            // whether or not to transform the rendered image before presenting
            .pre_transform = details.capabilities.current_transform,

            // whether to take the alpha channel into account to do cross-window blending (weird)
            .composite_alpha = .{ .opaque_bit_khr = true },

            // ignore obscured pixels (i.e covered by another window)
            .clipped = vk.TRUE,

            // old swapchain (used for swapchain recreation which will come later)
            .old_swapchain = .null_handle,
        }, null),
    };
    // TODO: Figure out a better deallocation strategy then this crap

    // get handles to the created images and create their associated views
    // (which has to be done AFTER the swapchain is created hence the var instead of const)
    try chain.createImageViews();

    return chain;
}

pub fn deinit(self: *const Self) void {
    for (self.images) |*info| {
        self.pr_dev.destroyImageView(info.h_view, null);
    }

    self.allocator.free(self.images);

    // NOTE: The image handles are owned by the swapchain and therefore shouold not be destroyed by me.
    self.pr_dev.destroySwapchainKHR(self.h_swapchain, null);
}

pub fn getNextImage(self: *Self, sem_signal: ?vk.Semaphore, fence_signal: ?vk.Fence) !u32 {
    const res = try self.pr_dev.acquireNextImageKHR(
        self.h_swapchain,
        std.math.maxInt(u64),
        sem_signal orelse .null_handle,
        fence_signal orelse .null_handle,
    );

    self.image_index = res.image_index;
    return res.image_index;
}
