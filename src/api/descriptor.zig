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
};

pub const LayoutBindings = struct {
    stages: vk.ShaderStageFlags,
    type: DescriptorType,
};

pub const ResolvedBinding = union(DescriptorType) {
    Uniform: struct {
        res: AnyBuffer,
        info: vk.DescriptorBufferInfo = undefined,
    },
    Sampler: struct {
        res: *const TexImage,
        info: vk.DescriptorImageInfo = undefined,
    },
};

/// ## Notes
/// The order you specify the bindings to the function
/// is the (0 indexed) order they be actually laid out
pub fn GenericDescriptor(comptime bind_info: []const LayoutBindings) type {
    const num_bindings = bind_info.len;
    return struct {
        const Self = @This();

        pub const Config = struct {
            // this gets copied to the actual array, so it can be specified locally no problemo
            bindings: []ResolvedBinding,
        };

        h_desc_layout: vk.DescriptorSetLayout,
        h_desc_pool: vk.DescriptorPool,
        h_desc_set: vk.DescriptorSet,
        pr_dev: *const vk.DeviceProxy,

        resolved_bindings: [num_bindings]ResolvedBinding = undefined,

        fn resolveDescriptorLayout(
            layouts: *[num_bindings]vk.DescriptorSetLayoutBinding,
        ) void {
            // I guess just ignore any extra bindings specified, not my problem lol
            for (0..num_bindings) |index| {
                layouts[index] = vk.DescriptorSetLayoutBinding{
                    .binding = @intCast(index),
                    .descriptor_count = 1,
                    .stage_flags = bind_info[index].stages,

                    .descriptor_type = switch (bind_info[index].type) {
                        .Sampler => .combined_image_sampler,
                        .Uniform => .uniform_buffer,
                    },
                };
            }
        }

        fn updateDescriptorSets(
            self: *Self,
            dev: *const DeviceHandler,
            bindings: []ResolvedBinding,
            desc_set: vk.DescriptorSet,
        ) void {
            var writes: [num_bindings]vk.WriteDescriptorSet = undefined;

            for (bindings, 0..num_bindings) |binding, index| {
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

                //FIX: GUHH fuck vulkan's struct pointers
                switch (binding) {
                    .Sampler => |*tex| {
                        log.debug("Guh: {x}", .{tex.res.view.h_view});
                        bindings[index].Sampler.info = vk.DescriptorImageInfo{
                            .image_layout = .read_only_optimal,
                            .image_view = tex.res.view.h_view,
                            .sampler = tex.res.h_sampler,
                        };

                        writes[index].descriptor_type = .combined_image_sampler;
                        writes[index].p_image_info = many(vk.DescriptorImageInfo, &bindings[index].Sampler.info);
                    },
                    .Uniform => |*buf| {
                        bindings[index].Uniform.info = vk.DescriptorBufferInfo{
                            .buffer = if (buf.res.handle == .null_handle) @panic("FUCK") else buf.res.handle,
                            .offset = 0,
                            .range = buf.res.size,
                        };

                        writes[index].descriptor_type = .uniform_buffer;
                        writes[index].p_buffer_info = many(vk.DescriptorBufferInfo, &bindings[index].Uniform.info);
                    }
                }
            }

            dev.pr_dev.updateDescriptorSets(
                @intCast(writes.len),
                writes[0..].ptr,
                0,
                null,
            );
        }

        pub fn init(ctx: *const Context, config: Config) !Self {
            const dev: *const DeviceHandler = ctx.env(.dev);

            if (config.bindings.len < num_bindings) {
                return error.InvalidBindings;
            }
            var bindings: [num_bindings]vk.DescriptorSetLayoutBinding = undefined;
            resolveDescriptorLayout(&bindings);

            const layout_info = vk.DescriptorSetLayoutCreateInfo{
                .binding_count = bindings.len,
                .p_bindings = bindings[0..],
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
            var descriptor = Self{
                .h_desc_layout = desc_layout,
                .h_desc_pool = desc_pool,
                .pr_dev = &dev.pr_dev,
                .h_desc_set = desc_set[0],
            };

            descriptor.updateDescriptorSets(dev, config.bindings, desc_set[0]);

            return descriptor;
        }

        pub fn bind(self: *const Self, cmd_buf: *const CommandBuffer, layout: vk.PipelineLayout) void {
            self.pr_dev.cmdBindDescriptorSets(
                cmd_buf.h_cmd_buffer,
                .graphics,
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
        }

        pub fn update(self: *Self, index: usize, data: anytype) !void {
            const binding = self.resolved_bindings[index];
            switch (binding) {
                .Uniform => |buf| {
                    try buf.res.setData(data);
                },
                .Sampler => {
                    log.err("Fuck (AKA no texture updating pretty please", .{});
                    return error.Unsupported;
                }
            }
        }
    };
}
