//! A pretty temporary implementation for
//! basic descriptor management in vulkan, manages it's own pool for now
const std = @import("std");

const vk = @import("vulkan");
const util = @import("../util.zig");
const uniform = @import("uniform.zig");
const buffer = @import("buffer.zig");

const many = util.asManyPtr;

const Allocator = std.mem.Allocator;

const DeviceHandler = @import("base.zig").DeviceHandler;
const UniformBuffer = uniform.UniformBuffer;
const CommandBuffer = @import("command_buffer.zig");
const Context = @import("../context.zig");

const AnyBuffer = buffer.AnyBuffer;

const TexImage = @import("texture.zig");
const Image = @import("image.zig");

const log = std.log.scoped(.descriptor);

fn createDescriptorPool(pr_dev: *const vk.DeviceProxy) !vk.DescriptorPool {
    return try pr_dev.createDescriptorPool(&.{
        // NOTE: In the future, pools and sets will be managed separately :)
        .pool_size_count = 1,
        .max_sets = 1,
        .p_pool_sizes = util.asManyPtr(vk.DescriptorPoolSize, &.{
            .type = .uniform_buffer,
            .descriptor_count = 1,
        }),
    }, null);
}

pub const DescriptorType = enum(u8) {
    Uniform,
    Sampler,
    StorageBuffer,
    Image,
};

pub const ResolvedBinding = struct {
    stages: vk.ShaderStageFlags,
    data: union(DescriptorType) {
        Uniform: AnyBuffer,
        Sampler: *const TexImage,
        StorageBuffer: AnyBuffer,
        Image: struct {
            img: *const Image,
            // caller is responsible for this for now
            view: vk.ImageView,
        },
    },
};

// flattened since buffers are the same regardless
// of whether they be uniform or storage
const BindingWriteInfo = union(enum) {
    Image: vk.DescriptorImageInfo,
    Buffer: vk.DescriptorBufferInfo,
};

/// ## Notes
/// The order you specify the bindings to the function
/// is the (0 indexed) order they be actually laid out
const Self = @This();

pub const Config = struct {
    // this gets copied to the actual array, so it can be specified locally no problemo
    bindings: []const ResolvedBinding,
};

h_desc_layout: vk.DescriptorSetLayout,
h_desc_pool: vk.DescriptorPool,
h_desc_set: vk.DescriptorSet,
pr_dev: *const vk.DeviceProxy,
allocator: Allocator,

resolved_bindings: []ResolvedBinding = undefined,

fn resolveDescriptorLayout(
    layouts: []vk.DescriptorSetLayoutBinding,
    bindings: []const ResolvedBinding,
) void {
    // I guess just ignore any extra bindings specified, not my problem lol
    for (0..layouts.len) |index| {
        layouts[index] = vk.DescriptorSetLayoutBinding{
            .binding = @intCast(index),
            .descriptor_count = 1,
            .stage_flags = bindings[index].stages,

            .descriptor_type = switch (bindings[index].data) {
                .Sampler => .combined_image_sampler,
                .Uniform => .uniform_buffer,
                .StorageBuffer => .storage_buffer,
                .Image => .storage_image,
            },
        };
    }
}

fn updateDescriptorSets(
    self: *Self,
    dev: *const DeviceHandler,
    desc_set: vk.DescriptorSet,
    allocator: Allocator,
) !void {
    const num_bindings = self.resolved_bindings.len;
    var writes: []vk.WriteDescriptorSet = try allocator.alloc(
        vk.WriteDescriptorSet,
        num_bindings,
    );
    defer allocator.free(writes);

    var write_infos: []BindingWriteInfo = try allocator.alloc(
        BindingWriteInfo,
        num_bindings,
    );
    defer allocator.free(write_infos);

    for (self.resolved_bindings, 0..num_bindings) |binding, index| {
        writes[index] = vk.WriteDescriptorSet{
            .descriptor_type = undefined,

            .dst_binding = @intCast(index),
            .dst_array_element = 0,
            .descriptor_count = 1,
            .dst_set = desc_set,

            .p_buffer_info = undefined,
            .p_image_info = undefined,
            .p_texel_buffer_view = undefined,
        };

        self.resolved_bindings[index] = binding;

        switch (binding.data) {
            .Sampler => |tex| {
                write_infos[index] = .{ .Image = vk.DescriptorImageInfo{
                    .image_layout = .read_only_optimal,
                    .image_view = tex.view.h_view,
                    .sampler = tex.h_sampler,
                } };

                writes[index].descriptor_type = .combined_image_sampler;
                writes[index].p_image_info = &.{write_infos[index].Image};
            },
            .Image => |img| {
                write_infos[index] = .{ .Image = vk.DescriptorImageInfo{
                    .image_layout = .general,
                    .image_view = img.view,
                    .sampler = .null_handle,
                } };

                writes[index].p_image_info = &.{write_infos[index].Image};
                writes[index].descriptor_type = .storage_image;
            },
            else => {
                const buf: AnyBuffer, const dt: vk.DescriptorType = switch (binding.data) {
                    .Uniform => |buf| .{ buf, .uniform_buffer },
                    .StorageBuffer => |buf| .{ buf, .storage_buffer },
                    else => unreachable,
                };

                write_infos[index] = .{ .Buffer = vk.DescriptorBufferInfo{
                    .buffer = buf.handle,
                    .offset = 0,
                    .range = buf.size,
                } };

                writes[index].descriptor_type = dt;

                writes[index].p_buffer_info = many(
                    vk.DescriptorBufferInfo,
                    &write_infos[index].Buffer,
                );
            },
        }
    }

    dev.pr_dev.updateDescriptorSets(
        @intCast(writes.len),
        writes[0..].ptr,
        0,
        null,
    );
}

pub fn init(ctx: *const Context, allocator: Allocator, config: Config) !Self {
    const dev: *const DeviceHandler = ctx.env(.dev);

    var desc_bindings = try allocator.alloc(
        vk.DescriptorSetLayoutBinding,
        config.bindings.len,
    );
    defer allocator.free(desc_bindings);

    resolveDescriptorLayout(desc_bindings, config.bindings);

    const layout_info = vk.DescriptorSetLayoutCreateInfo{
        .binding_count = @intCast(desc_bindings.len),
        .p_bindings = desc_bindings[0..].ptr,
    };

    const desc_layout = try dev.pr_dev.createDescriptorSetLayout(
        &layout_info,
        null,
    );

    const desc_pool = try createDescriptorPool(&dev.pr_dev);
    errdefer dev.pr_dev.destroyDescriptorPool(desc_pool, null);

    var desc_set = [_]vk.DescriptorSet{.null_handle};

    try dev.pr_dev.allocateDescriptorSets(&.{
        .descriptor_pool = desc_pool,
        .descriptor_set_count = 1,
        .p_set_layouts = many(vk.DescriptorSetLayout, &desc_layout),
    }, desc_set[0..]);

    // setup the bloody descriptor sets and associate them wit the buffer
    const owned_bindings = try allocator.alloc(
        ResolvedBinding,
        config.bindings.len,
    );
    errdefer allocator.free(owned_bindings);
    std.mem.copyForwards(ResolvedBinding, owned_bindings, config.bindings);

    var descriptor = Self{
        .h_desc_layout = desc_layout,
        .h_desc_pool = desc_pool,
        .pr_dev = &dev.pr_dev,
        .h_desc_set = desc_set[0],
        .resolved_bindings = owned_bindings,
        .allocator = allocator,
    };
    errdefer descriptor.deinit();

    try descriptor.updateDescriptorSets(dev, desc_set[0], allocator);

    return descriptor;
}

pub const BindInfo = struct {
    bind_point: vk.PipelineBindPoint = .graphics,
};

pub fn bind(
    self: *const Self,
    cmd_buf: *const CommandBuffer,
    layout: vk.PipelineLayout,
    info: BindInfo,
) void {
    self.pr_dev.cmdBindDescriptorSets(
        cmd_buf.h_cmd_buffer,
        info.bind_point,
        layout,
        0,
        1,
        many(vk.DescriptorSet, &self.h_desc_set),
        0,
        null,
    );
}

pub fn deinit(self: *Self) void {
    self.pr_dev.destroyDescriptorPool(self.h_desc_pool, null);
    self.pr_dev.destroyDescriptorSetLayout(self.h_desc_layout, null);

    self.allocator.free(self.resolved_bindings);
}

pub fn update(self: *Self, index: usize, data: anytype) !void {
    const binding = self.resolved_bindings[index];
    switch (binding.data) {
        .Uniform => |buf| try buf.setData(data),
        .StorageBuffer => |buf| try buf.setData(data),
        else => {
            log.err("Fuck (AKA no texture updating pretty please)", .{});
            return error.Unsupported;
        },
    }
}
