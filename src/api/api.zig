pub const vk = @import("vulkan");

const base = @import("base.zig");
const queue = @import("queue.zig");
const buf = @import("buffer.zig");
const desc = @import("descriptor.zig");
const ind_buf = @import("index_buffer.zig");
const sh = @import("shader.zig");
const uni_buf = @import("uniform.zig");
const vert_buf = @import("vertex_buffer.zig");

// direct vulkan-zig imports
pub const GlobalInterface = vk.BaseWrapper;
pub const InstanceInterface = vk.InstanceProxy;
pub const DeviceInterface = vk.DeviceProxy;
pub const Semaphore = vk.Semaphore;
pub const Fence = vk.Fence;
pub const DynamicState = vk.DynamicState;

/// All registered extensions for devices and instances
pub const extensions = vk.extensions;

pub const InstanceHandler = base.InstanceHandler; 
pub const DeviceHandler = base.DeviceHandler;
pub const SurfaceHandler = base.SurfaceHandler;

pub const GraphicsQueue = queue.GraphicsQueue;
pub const ComputeQueue = queue.ComputeQueue;
pub const PresentQueue = queue.PresentQueue;

pub const Swapchain = @import("swapchain.zig");
pub const FrameBuffer = @import("frame_buffer.zig");
pub const GraphicsPipeline = @import("graphics_pipeline.zig");
pub const RenderPass = @import("renderpass.zig");
pub const CommandBuffer = @import("command_buffer.zig");
pub const FixedFunctionState = GraphicsPipeline.FixedFunctionState;

// vulkan images (textures, depth images, and generic images)
pub const Image = @import("image.zig");
pub const DepthImage = @import("depth.zig");
pub const TexImage = @import("texture.zig");

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
