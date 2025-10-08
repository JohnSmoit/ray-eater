//! Basic example of compute shader initialization using the Low-Level
//! unmanaged Vulkan API.
//! NOTE: This example will likely be deprecated in favor of using the upcoming
//! Managed low level API (see milestone 0.1).
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

const Semaphore = api.Semaphore;
const Fence = api.Fence;

const GraphicsQueue = api.GraphicsQueue;
const PresentQueue = api.PresentQueue;

const UniformBuffer = api.ComptimeUniformBuffer;
const StorageBuffer = api.ComptimeStorageBuffer;
const Image = api.Image;
const Compute = api.Compute;

const log = std.log.scoped(.application);

const GraphicsState = struct {
    descriptor: Descriptor,
    framebuffers: FrameBuffer,
    render_quad: RenderQuad,

    cmd_buf: CommandBuffer,

    pub fn deinit(self: *GraphicsState) void {
        self.render_quad.deinit();
        self.framebuffers.deinit();
        self.cmd_buf.deinit();
        self.descriptor.deinit();
    }
};

const ApplicationUniforms = extern struct {
    transform: math.Mat4,
    resolution: math.Vec2,
    time: f32,
    aspect: f32,
};

const GPUState = struct {
    host_uniforms: ApplicationUniforms,

    // compute and graphics visible
    uniforms: UniformBuffer(ApplicationUniforms),

    // compute and graphics visible (needs viewport quad)
    // written to in the compute shader and simply mapped to the viewport

    pub fn deinit(self: *GPUState) void {
        self.uniforms.deinit();
    }
};

const SyncState = struct {
    sem_render: Semaphore,
    sem_acquire_frame: Semaphore,
    frame_fence: Fence,

    pub fn deinit(self: *const SyncState) void {
        self.sem_render.deinit();
        self.sem_acquire_frame.deinit();
        self.frame_fence.deinit();
    }
};

const SampleState = struct {
    ctx: *Context = undefined,
    swapchain: Swapchain = undefined,
    window: glfw.Window = undefined,
    allocator: Allocator,

    graphics: GraphicsState = undefined,
    gpu_state: GPUState = undefined,

    sync: SyncState = undefined,

    pub fn createContext(self: *SampleState) !void {
        self.window = try helpers.makeBasicWindow(900, 600, "Sacred Geometry");
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

    pub fn createGraphicsPipeline(self: *SampleState, file: []const u8) !void {
        const frag_shader = try helpers.initSampleShader(
            self.ctx,
            self.allocator,
            file,
            .Fragment,
        );

        defer frag_shader.deinit();

        const size = self.window.dimensions();
        // initialize uniforms
        self.gpu_state.host_uniforms = .{
            .time = 0,
            .transform = math.Mat4.identity(),
            .resolution = math.vec(.{ 1.0, 1.0 }),
            .aspect = @as(f32, @floatFromInt(size.height)) / @as(f32, @floatFromInt(size.width)),
        };

        self.gpu_state.uniforms = try UniformBuffer(ApplicationUniforms)
            .create(self.ctx);

        try self.gpu_state.uniforms.setData(&self.gpu_state.host_uniforms);

        // create fragment-specific descriptors
        self.graphics.descriptor = try Descriptor.init(self.ctx, self.allocator, .{ .bindings = &.{.{
            .data = .{ .Uniform = self.gpu_state.uniforms.buffer() },
            .stages = .{ .fragment_bit = true },
        }} });

        try self.graphics.render_quad.initSelf(self.ctx, self.allocator, .{
            .frag_shader = &frag_shader,
            .frag_descriptors = &self.graphics.descriptor,
            .swapchain = &self.swapchain,
        });

        self.graphics.framebuffers = try FrameBuffer.initAlloc(self.ctx, self.allocator, .{
            .depth_view = null,
            .swapchain = &self.swapchain,
            .renderpass = &self.graphics.render_quad.renderpass,
        });

        self.graphics.cmd_buf = try CommandBuffer.init(self.ctx, .{});
    }

    pub fn createSyncObjects(self: *SampleState) !void {
        self.sync.frame_fence = try Fence.init(self.ctx, true);
        self.sync.sem_acquire_frame = try Semaphore.init(self.ctx);
        self.sync.sem_render = try Semaphore.init(self.ctx);

        //compute sync objects
    }

    pub fn active(self: *const SampleState) bool {
        return !self.window.shouldClose();
    }

    fn updateUniforms(self: *SampleState) !void {
        self.gpu_state.host_uniforms.time = @floatCast(glfw.getTime());
        try self.gpu_state.uniforms.setData(&self.gpu_state.host_uniforms);
    }

    // intercepts errors and logs them
    pub fn update(self: *SampleState) !void {
        glfw.pollEvents();

        // wait for v
        try self.sync.frame_fence.wait();
        try self.sync.frame_fence.reset();

        try self.updateUniforms();

        _ = try self.swapchain.getNextImage(self.sync.sem_acquire_frame.h_sem, null);

        try self.graphics.cmd_buf.reset();
        try self.graphics.cmd_buf.begin();
        self.graphics.render_quad.drawOneShot(
            &self.graphics.cmd_buf,
            &self.graphics.framebuffers,
        );

        try self.graphics.cmd_buf.end();
        // submit the command buffer to a synchronized queue
        try self.ctx.submitCommands(&self.graphics.cmd_buf, .Graphics, .{
            .fence_wait = self.sync.frame_fence.h_fence,
            .sem_sig = self.sync.sem_render.h_sem,
            .sem_wait = self.sync.sem_acquire_frame.h_sem,
        });

        try self.ctx.presentFrame(&self.swapchain, .{
            .sem_wait = self.sync.sem_render.h_sem,
        });
    }

    pub fn deinit(self: *SampleState) void {
        self.ctx.dev.waitIdle() catch {};

        self.graphics.deinit();
        self.gpu_state.deinit();

        self.swapchain.deinit();

        self.sync.deinit();
        self.ctx.deinit();
        self.window.destroy();
    }
};

pub fn main() !void {
    const mem = try std.heap.page_allocator.alloc(u8, 1_000_024);
    var buf_alloc = FixedBufferAllocator.init(mem);
    defer std.heap.page_allocator.free(mem);

    var args = try std.process.argsWithAllocator(buf_alloc.allocator());
    _ = args.next();

    const shader_file = args.next() orelse {
        log.err("Usage: raymarch_fractal <shader_filename>", .{});
        return error.RequiresArgument;
    };

    var state: SampleState = .{
        .allocator = buf_alloc.allocator(),
    };

    // figure out the full path
    var path_builder = std.ArrayList(u8).init(buf_alloc.allocator());
    try path_builder.appendSlice("raymarch_fractals/shaders/");
    try path_builder.appendSlice(shader_file);
    std.debug.print("Full path: {s}\n", .{path_builder.items});

    try state.createContext();
    try state.createSyncObjects();
    try state.createSwapchain();
    try state.createGraphicsPipeline(path_builder.items);

    state.window.show();

    while (state.active()) {
        state.update() catch |err| {
            log.err("An error occured while running: {!}\n    ....Terminating", .{err});
            state.deinit();

            return err;
        };
    }

    state.deinit();
    log.info("You Win!", .{});
}
