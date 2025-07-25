const std = @import("std");
const ray = @import("ray");
const glfw = @import("glfw");
const helpers = @import("helpers");
const vk = @import("vulkan");

const api = ray.api;
const math = ray.math;

const Vec3 = math.Vec3;

const RenderQuad = helpers.RenderQuad;

const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const Allocator = std.mem.Allocator;

const Context = ray.Context;
const Swapchain = api.Swapchain;
const FrameBuffer = api.FrameBuffer;
const GraphicsPipeline = api.GraphicsPipeline;
const RenderPass = api.RenderPass;
const FixedFunctionState = api.FixedFunctionState;
const Descriptor = api.Descriptor;
const DescriptorBinding = api.ResolvedDescriptorBinding;
const CommandBuffer = api.CommandBuffer;

const GraphicsQueue = api.GraphicsQueue;
const PresentQueue = api.PresentQueue;

const UniformBuffer = api.ComptimeUniformBuffer;
const TexImage = api.Image;
const Compute = api.Compute;

const log = std.log.scoped(.application);

const GraphicsState = struct {
    framebuffers: FrameBuffer,
    render_quad: RenderQuad,

    cmd_buf: CommandBuffer,

    // pipeline for running slime simulation
    slime_pipeline: Compute,

    // pipeline for updating pheremone map
    stinky_pipeline: Compute,

    pub fn deinit(self: *GraphicsState) void {
        self.render_quad.deinit();
        self.framebuffers.deinit();
        self.cmd_buf.deinit();
    }
};

const ApplicationUniforms = extern struct {
    time: f32,
};

const GPUState = struct {
    host_uniforms: ApplicationUniforms,

    // compute and graphics visible
    uniforms: UniformBuffer(ApplicationUniforms),

    // compute and graphics visible (needs viewport quad)
    // written to in the compute shader and simply mapped to the viewport
    // with a few transformations for color and such.
    // ... This also represents the pheremone map that sim agents in the compute
    // shader would use to determine their movements
    //
    render_target: TexImage,

    // compute visible only
    // (contains source image data to base simulation off of)
    src_image: TexImage,

    // compute visible only
    // -- contains simulation agents
    //particles: StorageBuffer,
};

const SampleState = struct {
    ctx: *Context = undefined,
    swapchain: Swapchain = undefined,
    window: glfw.Window = undefined,
    allocator: Allocator,

    graphics: GraphicsState = undefined,
    gpu_state: GPUState = undefined,

    present_queue: PresentQueue = undefined,
    graphics_queue: GraphicsQueue = undefined,

    pub fn createContext(self: *SampleState) !void {
        self.window = try helpers.makeBasicWindow(900, 600, "BAD APPLE >:}");
        self.ctx = try Context.init(self.allocator, .{
            .inst_extensions = helpers.glfwInstanceExtensions(),
            .loader = glfw.glfwGetInstanceProcAddress,
            .window = &self.window,
        });
    }

    pub fn createSwapchain(self: *SampleState) !void {
        self.swapchain = try Swapchain.init(self.ctx, self.allocator, .{
            .requested_extent = helpers.windowExtent(&self.window),
            .requested_present_mode = .mailbox_khr,
            .requested_format = .{
                .color_space = .srgb_nonlinear_khr,
                .format = .r8g8b8a8_srgb,
            },
        });

    }

    pub fn retrieveDeviceQueues(self: *SampleState) !void {
        self.graphics_queue = try api.GraphicsQueue.init(self.ctx);
        self.present_queue = try api.PresentQueue.init(self.ctx);
    }

    pub fn createGraphicsPipeline(self: *SampleState) !void {
        const frag_shader = try helpers.initSampleShader(
            self.ctx,
            self.allocator,
            "slime/frag.glsl",
            .Fragment,
        );

        defer frag_shader.deinit();

        try self.graphics.render_quad.initSelf(self.ctx, self.allocator, .{
            .frag_shader = &frag_shader,
            .swapchain = &self.swapchain,
        });

        self.graphics.framebuffers = try FrameBuffer.initAlloc(self.ctx, self.allocator, .{
            .depth_view = null,
            .swapchain = &self.swapchain,
            .renderpass = &self.graphics.render_quad.renderpass,
        });

        self.graphics.cmd_buf = try CommandBuffer.init(self.ctx);
    }

    pub fn active(self: *const SampleState) bool {
        return !self.window.shouldClose();
    }

    // intercepts errors and logs them
    pub fn update(self: *SampleState) !void {
        glfw.pollEvents();

        try self.graphics.cmd_buf.reset();
        try self.graphics.cmd_buf.begin();
        self.graphics.render_quad.drawOneShot(
            &self.graphics.cmd_buf,
            &self.graphics.framebuffers,
        );

        try self.graphics.cmd_buf.end();
    }

    pub fn deinit(self: *SampleState) void {
        self.graphics.deinit();

        self.swapchain.deinit();
        self.ctx.deinit();
        self.window.destroy();
    }
};

pub fn main() !void {
    const mem = try std.heap.page_allocator.alloc(u8, 1_000_024);
    defer std.heap.page_allocator.free(mem);

    var buf_alloc = FixedBufferAllocator.init(mem);
    var state: SampleState = .{
        .allocator = buf_alloc.allocator(),
    };

    try state.createContext();
    try state.retrieveDeviceQueues();
    try state.createSwapchain();
    try state.createGraphicsPipeline();
    state.window.show();

    while (state.active()) {
        try state.update();
    }

    state.deinit();
    log.info("You Win!", .{});
}
