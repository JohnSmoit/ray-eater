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

const ComputeState = struct {
    // pipeline for running slime simulation
    slime_pipeline: Compute,
    // pipeline for updating pheremone map
    stinky_pipeline: Compute,

    cmd_buf: CommandBuffer,

    pub fn deinit(self: *ComputeState) void {
        self.slime_pipeline.deinit();
        self.cmd_buf.deinit();
    }
};

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
    time: f32,
    mouse: math.Vec2,
};

const ComputeUniforms = extern struct {
    col: math.Vec3,
    res_x: u32,
    res_y: u32,
    particle_count: u32,
    pixels_rad: u32,
};

const PARTICLE_COUNT = 1024;

const Particle = extern struct {
    position: math.Vec4,
};

const GPUState = struct {
    host_uniforms: ApplicationUniforms,

    // compute and graphics visible
    uniforms: UniformBuffer(ApplicationUniforms),
    compute_uniforms: UniformBuffer(ComputeUniforms),

    // compute and graphics visible (needs viewport quad)
    // written to in the compute shader and simply mapped to the viewport
    // with a few transformations for color and such.
    // ... This also represents the pheremone map that sim agents in the compute
    // shader would use to determine their movements
    //
    render_target: Image,
    render_view: Image.View,
    render_sampler: vk.Sampler,

    // compute visible only
    // (contains source image data to base simulation off of)
    src_image: Image,

    // compute visible only
    // -- contains simulation agents
    particles: StorageBuffer(Particle),

    pub fn deinit(self: *GPUState) void {
        self.particles.deinit();
        self.uniforms.deinit();
        self.compute_uniforms.deinit();

        self.render_view.deinit();
        self.render_target.deinit();
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
    compute: ComputeState = undefined,
    gpu_state: GPUState = undefined,

    sync: SyncState = undefined,

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

    pub fn createGraphicsPipeline(self: *SampleState) !void {
        const frag_shader = try helpers.initSampleShader(
            self.ctx,
            self.allocator,
            "slime/shaders/frag.glsl",
            .Fragment,
        );

        defer frag_shader.deinit();

        // initialize uniforms
        self.gpu_state.host_uniforms = .{
            .time = 0,
            .mouse = math.vec(.{ 0, 0 }),
        };

        self.gpu_state.uniforms = try UniformBuffer(ApplicationUniforms)
            .create(self.ctx);

        try self.gpu_state.uniforms.setData(&self.gpu_state.host_uniforms);

        // create fragment-specific descriptors
        self.graphics.descriptor = try Descriptor.init(self.ctx, self.allocator, .{
            .bindings = &.{ .{
                .data = .{ .Uniform = self.gpu_state.uniforms.buffer() },
                .stages = .{ .fragment_bit = true },
            }, DescriptorBinding{
                .data = .{ .Sampler = .{
                    .sampler = self.gpu_state.render_sampler,
                    .view = self.gpu_state.render_view.h_view,
                } },
                .stages = .{ .fragment_bit = true },
            } },
        });

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

    pub fn createComputePipelines(self: *SampleState) !void {
        self.compute.cmd_buf = try CommandBuffer.init(self.ctx, .{ .src_queue_family = .Compute });

        const shader = try helpers.initSampleShader(
            self.ctx,
            self.allocator,
            "slime/shaders/compute_slime.glsl",
            .Compute,
        );
        defer shader.deinit();
        // storage images
        self.gpu_state.render_target = try Image.init(self.ctx, .{
            .initial_layout = .general,
            .format = .r8g8b8a8_snorm,
            .tiling = .linear,
            .extent = self.swapchain.extent,
            .mem_flags = .{ .device_local_bit = true },
            .usage = .{
                .transfer_dst_bit = true,
                .storage_bit = true,
                .sampled_bit = true,
            },
            .clear_col = .{ .float_32 = .{ 0, 0, 0, 0 } },
        });
        self.gpu_state.render_view = try self.gpu_state.render_target.createView(.{ .color_bit = true });
        self.gpu_state.render_sampler = try self.gpu_state.render_target.getSampler(.{});

        self.gpu_state.compute_uniforms = try UniformBuffer(ComputeUniforms).create(self.ctx);
        self.gpu_state.particles = try StorageBuffer(Particle).create(self.ctx, PARTICLE_COUNT);

        const descriptors: []const DescriptorBinding = &.{
            .{
                .data = .{ .Uniform = self.gpu_state.compute_uniforms.buffer() },
                .stages = .{ .compute_bit = true },
            },
            .{
                .data = .{ .StorageBuffer = self.gpu_state.particles.buffer() },
                .stages = .{ .compute_bit = true },
            },
            .{
                .data = .{ .Image = .{
                    .img = &self.gpu_state.render_target,
                    .view = self.gpu_state.render_view.h_view,
                } },
                .stages = .{ .compute_bit = true },
            },
        };
        self.compute.slime_pipeline = try Compute.init(self.ctx, self.allocator, .{
            .shader = &shader,
            .desc_bindings = descriptors,
        });
    }

    pub fn initComputeData(self: *SampleState) !void {
        // initialize compute shader uniforms
        try self.gpu_state.compute_uniforms.setData(&ComputeUniforms{
            .col = math.vec(.{ 1.0, 1.0, 0.0 }),
            .particle_count = PARTICLE_COUNT,
            .pixels_rad = 20,
            .res_x = self.swapchain.extent.width,
            .res_y = self.swapchain.extent.height,
        });
        // randomize particle starting positions
        const seed: u64 = @intCast(@max(0, std.time.timestamp()));
        var rand_engine = std.Random.Sfc64.init(seed);
        const rand_generator = std.Random.init(
            &rand_engine,
            std.Random.Sfc64.fill,
        );

        const particles_temp = try self.allocator.alloc(Particle, PARTICLE_COUNT);

        const res_xf: f32 = @floatFromInt(self.swapchain.extent.width);
        const res_yf: f32 = @floatFromInt(self.swapchain.extent.height);

        for (particles_temp) |*particle| {
            particle.* = Particle{
                .position = math.vec(.{
                    rand_generator.float(f32) * res_xf,
                    rand_generator.float(f32) * res_yf,
                    0,
                    0,
                }),
            };
        }

        try self.gpu_state.particles.setData(particles_temp.ptr);
        log.debug("Successfully initialized compute shader data", .{});
    }

    pub fn testCompute(self: *SampleState) !void {
        const tmp_cmds = try CommandBuffer.oneShot(self.ctx.env(.dev), .{
            .src_queue_family = .Compute,
        });
        self.compute.slime_pipeline.bind(&tmp_cmds);
        self.compute.slime_pipeline.dispatch(&tmp_cmds, 4, 4, 1);
        try tmp_cmds.end();
        try tmp_cmds.submit(.Compute, .{});
        try self.ctx.dev.waitIdle();

        // transition render layout to shader sampler friendly
        try self.gpu_state.render_target.transitionLayout(.general, .shader_read_only_optimal, .{});
        try self.ctx.dev.waitIdle();
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
        self.compute.deinit();
        self.gpu_state.deinit();

        self.swapchain.deinit();

        self.sync.deinit();
        self.ctx.deinit();
        self.window.destroy();
    }
};

pub fn main() !void {
    log.debug("LINK START", .{});
    const mem = try std.heap.page_allocator.alloc(u8, 1_000_024);
    defer std.heap.page_allocator.free(mem);

    var buf_alloc = FixedBufferAllocator.init(mem);
    var state: SampleState = .{
        .allocator = buf_alloc.allocator(),
    };

    try state.createContext();
    try state.createSyncObjects();
    try state.createSwapchain();
    try state.createComputePipelines();
    try state.createGraphicsPipeline();
    try state.initComputeData();

    state.window.show();

    // test the compyuter shader
    try state.testCompute();

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
