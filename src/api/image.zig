const std = @import("std");
const vk = @import("vulkan");
const rsh = @import("rshc");

const buf = @import("buffer.zig");
const util = @import("../util.zig");

const Allocator = std.mem.Allocator;
const Context = @import("../context.zig");

const DeviceHandler = @import("base.zig").DeviceHandler;
const GraphicsQueue = @import("queue.zig").GraphicsQueue;

const CommandBuffer = @import("command_buffer.zig");

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
h_sampler: ?vk.Sampler = null,

dev: *const DeviceHandler = undefined,

format: vk.Format = .undefined,

pub const Config = struct {
    usage: vk.ImageUsageFlags,
    format: vk.Format,
    mem_flags: vk.MemoryPropertyFlags,
    extent: vk.Extent2D,

    tiling: vk.ImageTiling = .linear,
    clear_col: ?vk.ClearColorValue = null,
    staging_buf: ?*StagingBuffer = null,
    initial_layout: vk.ImageLayout = .undefined,
};

fn createImageMemory(
    dev: *const DeviceHandler,
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

pub const SamplerConfig = struct {
    mag_filter: vk.Filter = .linear,
    min_filter: vk.Filter = .linear,
    address_mode: vk.SamplerAddressMode = .repeat,
};

/// ## Notes
/// * lazily initializes the sampler if it doesnt exist
/// * the image owns the sampler so no need to destroy it manually
pub fn getSampler(self: *Self, config: SamplerConfig) !vk.Sampler {
    if (self.h_sampler) |s| return s;
    const max_aniso = self.dev.props.limits.max_sampler_anisotropy;

    self.h_sampler = try self.dev.pr_dev.createSampler(&.{
        .mag_filter = config.mag_filter,
        .min_filter = config.min_filter,

        .address_mode_u = config.address_mode,
        .address_mode_v = config.address_mode,
        .address_mode_w = config.address_mode,

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

    return self.h_sampler.?;
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

pub const AccessMapEntry = struct {
    stage: vk.PipelineStageFlags = .{},
    access: vk.AccessFlags = .{},
};

//NOTE: Unfortunately, vulkan enums (maybe also c enums in general)
// are too fat to work with the standard library's
// enum map (the compiler runs out of memory trying to allocate a 4-billion bit bitset
// along with a 4-billion entry array of my AccessMapEntry structs)
// probably worth looking into a static hashmap that works off of a predefined range of key-value
// entries and doesn't need allocation

fn getTransitionParams(layout: vk.ImageLayout) AccessMapEntry {
    return switch (layout) {
        .undefined => .{
            .stage = .{ .top_of_pipe_bit = true },
            .access = .{},
        },
        .general => .{
            .stage = .{ .compute_shader_bit = true },
            .access = .{},
        },
        .transfer_dst_optimal => .{
            .stage = .{ .transfer_bit = true },
            .access = .{ .transfer_write_bit = true },
        },
        .shader_read_only_optimal => .{
            .stage = .{ .fragment_shader_bit = true },
            .access = .{ .shader_read_bit = true },
        },
        else => extra: {
            log.warn("Invalid transition combination specified", .{});
            break :extra .{};
        },
    };
}

pub const LayoutTransitionOptions = struct {
    cmd_buf: ?*const CommandBuffer = null,
    src_access_overrides: vk.AccessFlags = .{},
    dst_access_overrides: vk.AccessFlags = .{},
};

/// injects a layout transition command into an existing command buffer
/// barriers included.
/// Command buffer MUST be specified in opts
pub fn cmdTransitionLayout(
    self: *Self,
    from: vk.ImageLayout,
    to: vk.ImageLayout,
    opts: LayoutTransitionOptions,
) void {
    const cmd_buf = opts.cmd_buf orelse return;

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

    const src_properties: AccessMapEntry = getTransitionParams(from);
    const dst_properties: AccessMapEntry = getTransitionParams(to);

    const default_src_access: vk.AccessFlags = src_properties.access;
    const default_dst_access: vk.AccessFlags = dst_properties.access;

    transition_barrier.src_access_mask =
        default_src_access.merge(opts.src_access_overrides);
    transition_barrier.dst_access_mask =
        default_dst_access.merge(opts.dst_access_overrides);

    log.debug("src access: {s}", .{transition_barrier.src_access_mask});
    log.debug("dst access: {s}", .{transition_barrier.dst_access_mask});

    self.dev.pr_dev.cmdPipelineBarrier(
        cmd_buf.h_cmd_buffer,
        src_properties.stage,
        dst_properties.stage,
        .{}, // allows for regional reading from the resource
        0,
        null,
        0,
        null,
        1,
        &.{transition_barrier},
    );
}

/// opts command buffer is ignored if specified
pub fn transitionLayout(
    self: *Self,
    from: vk.ImageLayout,
    to: vk.ImageLayout,
    opts: LayoutTransitionOptions,
) !void {
    const transition_cmds = try CommandBuffer.oneShot(self.dev, .{});
    defer transition_cmds.deinit();

    const opts2 = LayoutTransitionOptions{
        .src_access_overrides = opts.src_access_overrides,
        .dst_access_overrides = opts.dst_access_overrides,
        .cmd_buf = &transition_cmds,
    };

    self.cmdTransitionLayout(from, to, opts2);

    try transition_cmds.end();
    try transition_cmds.submit(.Graphics, .{});
}

fn copyFromStaging(self: *Self, staging_buf: *StagingBuffer, extent: vk.Extent3D) !void {
    const copy_cmds = try CommandBuffer.oneShot(self.dev, .{});
    defer copy_cmds.deinit();

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

    try copy_cmds.submit(.Graphics, .{});
}

pub fn cmdClear(
    self: *Self,
    col: vk.ClearColorValue,
    cmd_buf: *const CommandBuffer,
    cur_layout: vk.ImageLayout,
) void {
    self.dev.pr_dev.cmdClearColorImage(
        cmd_buf.h_cmd_buffer,
        self.h_img,
        cur_layout,
        &col,
        1,
        &.{.{
            .aspect_mask = .{ .color_bit = true },
            .base_array_layer = 0,
            .layer_count = 1,
            .base_mip_level = 0,
            .level_count = 1,
        }},
    );
}

fn initSelf(self: *Self, dev: *const DeviceHandler, config: Config) !void {
    const image_info = vk.ImageCreateInfo{
        .image_type = .@"2d",
        .extent = .{
            .width = config.extent.width,
            .height = config.extent.height,
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
        try self.transitionLayout(.undefined, .transfer_dst_optimal, .{});
        try self.copyFromStaging(config.staging_buf.?, image_info.extent);
        try self.transitionLayout(.transfer_dst_optimal, config.initial_layout, .{});
    } else {
        // WARN: This disregards the fact that if a staging buffer is not used, then
        // the user is probably copying from host visible memory (not sure if this handles that
        // correctly)
        const tmp_cmds = try CommandBuffer.oneShot(self.dev, .{});
        defer tmp_cmds.deinit();

        if (config.clear_col) |col| {
            self.cmdTransitionLayout(.undefined, .transfer_dst_optimal, .{
                .cmd_buf = &tmp_cmds,
            });
            self.cmdClear(col, &tmp_cmds, .transfer_dst_optimal);
            self.cmdTransitionLayout(.transfer_dst_optimal, config.initial_layout, .{
                .cmd_buf = &tmp_cmds,
            });
        } else {
            self.cmdTransitionLayout(.undefined, config.initial_layout, .{
                .cmd_buf = &tmp_cmds,
            });
        }

        try tmp_cmds.end();
        try tmp_cmds.submit(.Graphics, .{});
    }
}

pub fn init(ctx: *const Context, config: Config) !Self {
    var image = Self{};
    try image.initSelf(ctx.env(.dev), config);

    log.debug("successfully initiailized image", .{});
    return image;
}

/// creates an image from an image file.
/// Image parameters will be tuned for usage as a texture 
/// more so than a general purpose image for now...
pub fn fromFile(ctx: *const Context, allocator: Allocator, path: []const u8) !Self {
    var image_data = rsh.loadImageFile(path, allocator) catch |err| {
        log.err("Failed to load image: {!}", .{err});
        return err;
    };

    defer image_data.deinit();

    var staging_buffer = try StagingBuffer.create(ctx, image_data.imageByteSize());

    try staging_buffer.buffer().setData(image_data.pixels.asBytes().ptr);
    defer staging_buffer.deinit();

    const image = try Self.init(ctx, &.{
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
    if (self.h_sampler) |s| {
        self.dev.pr_dev.destroySampler(s, null);
    }

    self.dev.pr_dev.destroyImage(self.h_img, null);
    self.dev.pr_dev.freeMemory(self.h_mem, null);
}
