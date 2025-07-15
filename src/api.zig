pub const vk = @import("vulkan");

const vkb = @import("api/vulkan.zig");
const buf = @import("api/buffer.zig");
const desc = @import("api/descriptor.zig");
const ind_buf = @import("api/index_buffer.zig");
const sh = @import("api/shader.zig");
const uni_buf = @import("api/uniform.zig");
const vert_buf = @import("api/vertex_buffer.zig");

// direct vulkan-zig imports
pub const GlobalInterface = vk.BaseWrapper;
pub const InstanceInterface = vk.InstanceProxy;
pub const DeviceInterface = vk.DeviceProxy;
pub const Semaphore = vk.Semaphore;
pub const Fence = vk.Fence;
pub const DynamicState = vk.DynamicState;

/// All registered extensions for devices and instances
pub const extensions = vk.extensions;

// vulkan base types
pub const VulkanAPI = vkb.VulkanAPI;

pub const Instance = vkb.Context; 
pub const Device = vkb.Device;
pub const Surface = vkb.Surface;
pub const Swapchain = vkb.Swapchain;
pub const GraphicsQueue = vkb.GraphicsQueue;
pub const ComputeQueue = vkb.ComputeQueue;
pub const PresentQueue = vkb.PresentQueue;
pub const FrameBuffer = vkb.FrameBufferSet;
pub const GraphicsPipeline = vkb.GraphicsPipeline;
pub const RenderPass = vkb.RenderPass;
pub const CommandBuffer = vkb.CommandBufferSet;
pub const FixedFunctionState = vkb.FixedFunctionState;

// vulkan images (textures, depth images, and generic images)
pub const Image = @import("api/image.zig");
pub const DepthImage = @import("api/depth.zig");
pub const TexImage = @import("api/texture.zig");

// buffers and descriptors
pub const ComptimeVertexBuffer = vert_buf.VertexBuffer;
pub const ComptimeIndexBuffer = ind_buf.IndexBuffer;
pub const ComptimeUniformBuffer = uni_buf.UniformBuffer;
pub const BufInterface = buf.AnyBuffer;

pub const ComptimeDescriptor = desc.GenericDescriptor;
pub const DescriptorBinding = desc.LayoutBindings;
pub const ResolvedDescriptorBinding = desc.ResolvedBinding;

// shaders
pub const ShaderModule = sh.Module;
