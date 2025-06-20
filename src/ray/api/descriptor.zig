//! A pretty temporary implementation for
//! basic descriptor management in vulkan, manages it's own pool for now
const vk = @import("vulkan");
const api = @import("vulkan.zig");
const util = @import("../util.zig");
const uniform = @import("uniform.zig");

const many = util.asManyPtr;

const Device = api.Device;
const UniformBuffer = uniform.UniformBuffer;
const CommandBufferSet = api.CommandBufferSet;

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

pub fn GenericDescriptor(T: type) type {
    return struct {
        const Self = @This();
        const UBOType = UniformBuffer(T);

        pub const Config = struct {
            stages: vk.ShaderStageFlags,
        };

        h_desc_layout: vk.DescriptorSetLayout,
        h_desc_pool: vk.DescriptorPool,
        h_desc_set: vk.DescriptorSet,
        pr_dev: *const vk.DeviceProxy,
        ubo: UBOType,

        pub fn init(dev: *const Device, config: Config) !Self {
            const ubo_binding = vk.DescriptorSetLayoutBinding{
                .binding = 0,
                .descriptor_type = .uniform_buffer,
                .descriptor_count = 1,
                .stage_flags = config.stages,
            };

            const layout_info = vk.DescriptorSetLayoutCreateInfo{
                .binding_count = 1,
                .p_bindings = many(vk.DescriptorSetLayoutBinding, &ubo_binding),
            };

            const desc_layout = try dev.pr_dev.createDescriptorSetLayout(
                &layout_info,
                null,
            );

            const desc_pool = try createDescriptorPool(&dev.pr_dev);
            errdefer dev.pr_dev.destroyDescriptorPool(desc_pool, null);

            var desc_set = [_]vk.DescriptorSet{.null_handle};
            var ubo = try UBOType.create(dev);
            errdefer ubo.buffer().deinit();

            try dev.pr_dev.allocateDescriptorSets(&.{
                .descriptor_pool = desc_pool,
                .descriptor_set_count = 1,
                .p_set_layouts = many(vk.DescriptorSetLayout, &desc_layout),
            }, desc_set[0..]);

            // setup the bloody descriptor sets and associate them wit the bufferd
            const desc_write = vk.WriteDescriptorSet{
                .dst_set = desc_set[0],
                .dst_binding = 0,
                .dst_array_element = 0,
                .descriptor_type = .uniform_buffer,
                .descriptor_count = 1,
                .p_buffer_info = many(vk.DescriptorBufferInfo, &.{
                    .buffer = ubo.buf.h_buf,
                    .offset = 0,
                    .range = ubo.buf.bytesSize(),
                }),
                .p_image_info = &[0]vk.DescriptorImageInfo{},
                .p_texel_buffer_view = &[0]vk.BufferView{},
            };

            dev.pr_dev.updateDescriptorSets(
                1,
                many(vk.WriteDescriptorSet, &desc_write),
                0,
                null,
            );

            return Self{
                .h_desc_layout = desc_layout,
                .ubo = ubo,
                .h_desc_pool = desc_pool,
                .pr_dev = &dev.pr_dev,
                .h_desc_set = desc_set[0],
            };
        }

        pub fn bind(self: *const Self, cmd_buf: *const CommandBufferSet, layout: vk.PipelineLayout) void {
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

            // NOTE: Totally botched the vtable interface implementation LOL (pls redo post bootstrap)
            self.ubo.buffer().deinit();
        }

        pub fn update(self: *Self, data: *const T) !void {
            try self.ubo.buffer().setData(data);
        }
    };
}
