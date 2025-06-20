//! A pretty temporary implementation for
//! basic descriptor management in vulkan, manages it's own pool for now
const vk = @import("vulkan");
const api = @import("vulkan.zig");
const util = @import("../util.zig");
const uniform = @import("uniform.zig");

const many = util.asManyPtr;

const Device = api.Device;
const UniformBuffer = uniform.UniformBuffer;

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

            return Self{
                .h_desc_layout = try dev.pr_dev.createDescriptorSetLayout(
                    &layout_info,
                    null,
                ),
                .ubo = try UBOType.create(dev),
            };
        }

        pub fn deinit(self: *const Self) void {
            self.pr_dev.destroyDescriptorSetLayout(self.h_desc_layout, null);
            
            // NOTE: Totally botched the vtable interface implementation LOL (pls redo post bootstrap)
            self.ubo.buffer().deinit();
        }

        pub fn update(self: *Self, data: *const T) !void {
            try self.ubo.buffer().setData(data);
        }
    };
}
