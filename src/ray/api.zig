const vk = @import("vulkan");

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

// vulkan base types
pub const Instance = vkb.Context; 
pub const Device = vkb.Device;
pub const Surface = vkb.Surface;
pub const Swapchain = vkb.Swapchain;
pub const GraphicsQueue = vkb.GraphicsQueue;
pub const ComputeQueue = vkb.ComputeQueue;
pub const PresentQueue = vkb.PresentQueue;
pub const Framebuffer = vkb.FrameBufferSet;
pub const GraphicsPipeline = vkb.GraphicsPipeline;
pub const RenderPass = vkb.RenderPass;
pub const CommandBuffer = vkb.CommandBufferSet;

// vulkan images (textures, depth images, and generic images)
pub const Image = @import("api/image.zig");
pub const DepthImage = @import("api/depth.zig");
pub const TexImage = @import("api/texture.zig");

// buffers and descriptors
pub const ComptimeVertexBuffer = vert_buf.VertexBuffer;
pub const ComptimeIndexBuffer = ind_buf.IndexBuffer;
pub const ComptimeUniformbuffer = uni_buf.UniformBuffer;
pub const ComptimeDescriptor = desc.GenericDescriptor;

// shaders
pub const Shader = sh.Module;
