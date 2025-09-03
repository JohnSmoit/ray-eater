pub const vk = @import("vulkan");

const base = @import("base.zig");
const queue = @import("queue.zig");
const sync = @import("sync.zig");
const buf = @import("buffer.zig");
const ind_buf = @import("index_buffer.zig");
const sh = @import("shader.zig");
const uni_buf = @import("uniform.zig");
const vert_buf = @import("vertex_buffer.zig");
const common = @import("common_types.zig");

// direct vulkan-zig imports
pub const GlobalInterface = *const vk.BaseWrapper;
pub const InstanceInterface = *const vk.InstanceProxy;
pub const DeviceInterface = *const vk.DeviceProxy;
pub const DynamicState = vk.DynamicState;

/// All registered extensions for devices and instances
pub const extensions = vk.extensions;

pub const InstanceHandler = base.InstanceHandler; 
pub const DeviceHandler = base.DeviceHandler;
pub const SurfaceHandler = base.SurfaceHandler;

pub const GraphicsQueue = queue.GraphicsQueue;
pub const ComputeQueue = queue.ComputeQueue;
pub const PresentQueue = queue.PresentQueue;
pub const GenericQueue = queue.GenericQueue;
pub const QueueType = queue.QueueFamily;

pub const Swapchain = @import("swapchain.zig");
pub const FrameBuffer = @import("frame_buffer.zig");
pub const GraphicsPipeline = @import("graphics_pipeline.zig");
pub const RenderPass = @import("renderpass.zig");
pub const CommandBuffer = @import("command_buffer.zig");
pub const FixedFunctionState = GraphicsPipeline.FixedFunctionState;

// Compute (all by its lonesome)
pub const Compute = @import("compute.zig");

// vulkan images (textures, depth images, and generic images)
pub const Image = @import("image.zig");
pub const DepthImage = @import("depth.zig");
pub const TexImage = @import("texture.zig");

// buffers and descriptors
pub const ComptimeVertexBuffer = vert_buf.VertexBuffer;
pub const ComptimeIndexBuffer = ind_buf.IndexBuffer;
pub const ComptimeUniformBuffer = uni_buf.UniformBuffer;
pub const ComptimeStorageBuffer = @import("storage_buffer.zig").ComptimeStorageBuffer;
pub const BufInterface = buf.AnyBuffer;

pub const Descriptor = @import("descriptor.zig");
pub const DescriptorPool = @import("descriptor_pool.zig");
pub const DescriptorLayout = Descriptor.DescriptorLayout;
pub const DescriptorType = common.DescriptorType;
pub const DescriptorUsageInfo = common.DescriptorUsageInfo;

// additional utility structs and stuff
const types = @import("common_types.zig");
pub const SyncInfo = types.SyncInfo;

// sync stuff
pub const Semaphore = sync.Semaphore;
pub const Fence = sync.Fence;

// shaders
pub const ShaderModule = sh.Module;

// Obtaining RTTI for vulkan API
const Registry = @import("../resource_management/res.zig").Registry;

pub fn initRegistry(reg: *Registry) !void {
    try CommandBuffer.addEntries(reg);
}
