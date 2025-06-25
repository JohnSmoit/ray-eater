const std = @import("std");
const vk = @import("vulkan");
const rsh = @import("rshc");

const api = @import("vulkan.zig");
const buf = @import("buffer.zig");
const util = @import("../util.zig");

const Allocator = std.mem.Allocator;

const CommandBufferSet = api.CommandBufferSet;
const Device = api.Device;
const GraphicsQueue = api.GraphicsQueue;
const StagingBuffer = buf.GenericBuffer(u8, .{
    .usage = .{ .transfer_src_bit = true },
    .memory = .{
        .host_visible_bit = true,
        .host_coherent_bit = true,
    },
});

const many = util.asManyPtr;

const Self = @This();

const log = std.log.scoped(.image);

pub const View = struct {
    h_view: vk.ImageView,
    pr_dev: *const vk.DeviceProxy,

    pub fn deinit(self: *const View) void {
        self.pr_dev.destroyImageView(self.h_view, null);
    }
};

h_img: vk.Image = .null_handle,
h_mem: vk.DeviceMemory = .null_handle,

dev: *const Device = undefined,

format: vk.Format = .undefined,

pub const Config = struct {
    usage: vk.ImageUsageFlags,
    format: vk.Format,
    tiling: vk.ImageTiling,
    mem_flags: vk.MemoryPropertyFlags,
    width: u32,
    height: u32,
    staging_buf: ?*StagingBuffer = null,
    initial_layout: vk.ImageLayout,
};

// NOTE: Yet another instance of a BAD function that allocates device memory in a non-zig like fashion
// -- memory allocator for device memory coming soon!
fn createImageMemory(
    dev: *const Device,
    img: vk.Image,
    flags: vk.MemoryPropertyFlags,
) !vk.DeviceMemory {
    const mem_reqs = dev.pr_dev.getImageMemoryRequirements(img);

    const mem = dev.pr_dev.allocateMemory(&.{
        .allocation_size = mem_reqs.size,
        .memory_type_index = try dev.findMemoryTypeIndex(
            mem_reqs,
            flags,
        ),
    }, null) catch |err| {
        log.err("Failed to allocate image memory: {!}", .{err});
        return err;
    };

    dev.pr_dev.bindImageMemory(img, mem, 0) catch |err| {
        log.err("The fuckin image memoryu bind failed waht the fuavk bro: {!}", .{err});
        return err;
    };

    return mem;
}

pub fn createView(self: *const Self, aspect_mask: vk.ImageAspectFlags) !View {
    const view = try self.dev.pr_dev.createImageView(&.{
        .image = self.h_img,
        .view_type = .@"2d",
        .format = self.format,
        .components = .{
            .r = .identity,
            .g = .identity,
            .b = .identity,
            .a = .identity,
        },
        .subresource_range = .{
            .aspect_mask = aspect_mask,
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    }, null);

    return .{
        .h_view = view,
        .pr_dev = &self.dev.pr_dev,
    };
}

pub fn transitionLayout(
    self: *Self,
    from: vk.ImageLayout,
    to: vk.ImageLayout,
) !void {
    const transition_cmds = try CommandBufferSet.oneShot(self.dev);
    defer transition_cmds.deinit();

    var transition_barrier = vk.ImageMemoryBarrier{
        .old_layout = from,
        .new_layout = to,

        // Used to transfer queue ownership of the resource, which must be done if
        // sharing mode is EXCLUSIVE.
        // NOTE: Apparently, this might also be used in external API transfers for resources,
        // which might be something I need to take into consideration, since drop-in renderer support is one
        // of my 3 **MAIN FEATURES**
        .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,

        .image = self.h_img,

        // This is how you specify parts of an image/resource that you want the barrier to effect
        .subresource_range = .{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },

        // these are setup once we figure out the actual pipline stages
        // of the barrier
        .dst_access_mask = undefined,
        .src_access_mask = undefined,
    };

    // Specifying pipeline stages for the transition:
    // This is relatively straightforwards, but there are a couple of things to keep in mind
    // as far as specifying the pipeline stages the barrier sits between, as well as which parts
    // of the resource should be accessed as the source and destination of the barrier transition

    var src_stage = vk.PipelineStageFlags{}; // pipeline stage to happen before the barrier
    var dst_stage = vk.PipelineStageFlags{}; // pipeline stage to happen after the barrier

    if (from == .undefined and to == .transfer_dst_optimal) {
        // Technically, you could be implicit about this, since command buffers implicitly include
        // a .host_write_bit when submitted, but that's yucky
        transition_barrier.src_access_mask = .{};
        transition_barrier.dst_access_mask = .{ .transfer_write_bit = true };

        src_stage = .{ .top_of_pipe_bit = true };
        dst_stage = .{ .transfer_bit = true };
    } else if (from == .transfer_dst_optimal and to == .shader_read_only_optimal) {
        transition_barrier.src_access_mask = .{ .transfer_write_bit = true };
        transition_barrier.dst_access_mask = .{ .shader_read_bit = true };

        src_stage = .{ .transfer_bit = true };
        dst_stage = .{ .fragment_shader_bit = true };
    } else {
        log.err("Not a supported layout transition (This function is not generalized for all transitions)", .{});
        return error.Fuck;
    }

    self.dev.pr_dev.cmdPipelineBarrier(
        transition_cmds.h_cmd_buffer,
        src_stage,
        dst_stage,
        .{}, // allows for regional reading from the resource
        0,
        null,
        0,
        null,
        1,
        //TODO: Priority Uno -- This many pointer function is really cumbersome
        many(vk.ImageMemoryBarrier, &transition_barrier),
    );

    //TODO: one shot command buffers should auto submit when they end...
    transition_cmds.end() catch |err| {
        return err;
    };
}

fn copyFromStaging(self: *Self, staging_buf: *StagingBuffer, extent: vk.Extent3D) !void {
    const copy_cmds = try CommandBufferSet.oneShot(self.dev);

    self.dev.pr_dev.cmdCopyBufferToImage(
        copy_cmds.h_cmd_buffer,
        staging_buf.h_buf,
        self.h_img,
        .transfer_dst_optimal,
        1,
        many(vk.BufferImageCopy, &vk.BufferImageCopy{
            .buffer_offset = 0,
            .buffer_row_length = 0,
            .buffer_image_height = 0,

            .image_subresource = .{
                .aspect_mask = .{ .color_bit = true },
                .mip_level = 0,
                .base_array_layer = 0,
                .layer_count = 1,
            },

            .image_offset = .{ .x = 0, .y = 0, .z = 0 },
            .image_extent = extent,
        }),
    );

    copy_cmds.end() catch |err| {
        log.err("Image copy from staging buffer failed: {!}", .{err});
        return err;
    };
}

fn init_self(self: *Self, dev: *const Device, config: *const Config) !void {
    const image_info = vk.ImageCreateInfo{
        .image_type = .@"2d",
        .extent = .{
            .width = config.width,
            .height = config.height,
            .depth = 1,
        },
        .mip_levels = 1,
        .array_layers = 1,

        .format = config.format,
        .tiling = config.tiling,

        .initial_layout = .undefined,
        .usage = config.usage,

        .sharing_mode = .exclusive,
        .samples = .{ .@"1_bit" = true },
    };

    const img = dev.pr_dev.createImage(&image_info, null) catch |err| {
        log.err("Failed to create image: {!}", .{err});
        return err;
    };

    self.h_img = img;
    self.h_mem = try createImageMemory(dev, img, config.mem_flags);
    self.dev = dev;
    self.format = config.format;

    // image layout transitions
    // NOTE: We actually need to to 2 layout transitions,
    // 1. Transition from the intial image's layout to TRANSFER_DST_OPTIMAL so that the staging buffer
    // can be copied into the image's memory.
    //  - Previously to this, the image had no layout since it was newly created, hence the UNDEFINED initial layout
    // 2. Transition from TRANSFER_DST_OPTIMAL to SHADER_READ_ONLY_OPTIMAL to prepare the image to be used a sampler
    // (Which obviously is accessed as read only from the shader using the sampler as an intermediary)


    if (config.initial_layout == .undefined) {
        return;
    }

    if (config.staging_buf != null) {
        try self.transitionLayout(.undefined, .transfer_dst_optimal);
        try self.copyFromStaging(config.staging_buf.?, image_info.extent);
        try self.transitionLayout(.transfer_dst_optimal, config.initial_layout);
    } else {
        // NOTE: This disregards the fact that if a staging buffer is not used, then
        // the user is probably copying from host visible memory (not sure if this handles that
        // correctly)
        try self.transitionLayout(.undefined, config.initial_layout);
    }
}

pub fn init(dev: *const Device, config: *const Config) !Self {
    var image = Self{};
    try image.init_self(dev, config);

    return image;
}

/// creates a texture image and loads it from a provided file
/// WARN: This is a shit way of differentiating images between textures and other image types
/// Actually, this is shit in general, like this shit should be in the texture.zig like wtf
pub fn fromFile(dev: *const Device, path: []const u8, allocator: Allocator) !Self {
    var image_data = rsh.loadImageFile(path, allocator) catch |err| {
        log.err("Failed to load image: {!}", .{err});
        return err;
    };

    defer image_data.deinit();

    var staging_buffer = try StagingBuffer.create(dev, image_data.imageByteSize());

    try staging_buffer.buffer().setData(image_data.pixels.asBytes().ptr);
    defer staging_buffer.deinit();

    const image = try Self.init(dev, &.{
        .format = .r8g8b8a8_srgb,
        .tiling = .optimal,

        .height = @intCast(image_data.height),
        .width = @intCast(image_data.width),

        .usage = .{ .transfer_dst_bit = true, .sampled_bit = true },
        .mem_flags = .{ .device_local_bit = true },
        .staging_buf = &staging_buffer,
        .initial_layout = .shader_read_only_optimal,
    });

    return image;
}

pub fn deinit(self: *const Self) void {
    self.dev.pr_dev.destroyImage(self.h_img, null);
    self.dev.pr_dev.freeMemory(self.h_mem, null);
}
