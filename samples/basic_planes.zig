//! This application demonstrates a basic application
//! using the provided vulkan wrappers to do some basic polygon rendering with
//! textures and some basic shader work.

const std = @import("std");

const ray = @import("ray");
const math = ray.math;
const api = ray.api;

const helpers = @import("helpers");
const util = ray.util;

const span = util.span;

const glfw = @import("glfw");
const Window = glfw.Window;

const Context = ray.Context;

const Allocator = std.mem.Allocator;

const root_log = std.log.scoped(.root);
const glfw_log = std.log.scoped(.glfw);

const vk_true = api.vk.TRUE;

// **************************************
// =============VULKAN STATE=============
// **************************************

var external_extensions: ?[][*:0]const u8 = null;

var context: *Context = undefined;

var swapchain: api.Swapchain = undefined;

var window_handle: *glfw.Window = undefined;

var renderpass: api.RenderPass = undefined;

var graphics_pipeline: api.GraphicsPipeline = undefined;

// rendering stuff
var framebuffers: api.FrameBuffer = undefined;
var depth_image: api.DepthImage = undefined;

var command_buffer: api.CommandBuffer = undefined;

const validation_layers: [1][*:0]const u8 = .{"VK_LAYER_KHRONOS_validation"};
const device_extensions = [_][*:0]const u8{api.extensions.khr_swapchain.name};

var render_finished_semaphore: api.Semaphore = undefined;
var image_finished_semaphore: api.Semaphore = undefined;
var present_finished_fence: api.Fence = undefined;

var dev: *const api.DeviceHandler = undefined;
var pr_dev: *const api.DeviceInterface = undefined;

const TestVertexInput = extern struct {
    position: math.Vec3,
    color: math.Vec3,
    uv: math.Vec2,
};

const TestUniforms = extern struct {
    model: math.Mat4,
    view: math.Mat4,
    projection: math.Mat4,
};

const UniformBuffer = api.ComptimeUniformBuffer(TestUniforms);
const VertexBuffer = api.ComptimeVertexBuffer(TestVertexInput);
const IndexBuffer = api.ComptimeIndexBuffer(u16);

var test_uniforms: TestUniforms = undefined;

var vertex_buffer: VertexBuffer = undefined;
var index_buffer: IndexBuffer = undefined;
var uniform_buffer: UniformBuffer = undefined;

var test_descriptor: api.Descriptor = undefined;
var test_tex: api.Image = undefined;
var test_tex_view: api.Image.View = undefined;

fn glfwErrorCallback(code: c_int, desc: [*c]const u8) callconv(.c) void {
    glfw_log.err("error code {d} -- Message: {s}", .{ code, desc });
}

fn init(allocator: Allocator) !void {
    _ = glfw.setErrorCallback(glfwErrorCallback);

    // scratch (Arena) allocator for memory stuff
    // NOTE: do NOT use this for allocations that are supposed to be persistent
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();

    var extensions = std.ArrayList([*:0]const u8).init(allocator);
    defer extensions.deinit();

    try extensions.appendSlice(external_extensions orelse &[0][*:0]const u8{});
    try extensions.appendSlice(&[_][*:0]const u8{
        // vk.extensions.khr_portability_enumeration.name, // renderdoc no likee this one
        api.extensions.khr_get_physical_device_properties_2.name,
        api.extensions.ext_debug_utils.name,
    });

    context = try Context.init(allocator, .{
        .inst_extensions = extensions.items,
        .dev_extensions = device_extensions[0..],
        .window = window_handle,
        .loader = glfw.glfwGetInstanceProcAddress,
    });

    dev = context.env(.dev);
    pr_dev = context.env(.di);

    swapchain = try api.Swapchain.init(context, allocator, .{
        .requested_present_mode = .mailbox_khr,
        .requested_format = .{
            .color_space = .srgb_nonlinear_khr,
            .format = .r8g8b8a8_srgb,
        },
        .requested_extent = .{
            .width = 900, // hardcoded for my sanity
            .height = 600,
        },
    });
    errdefer swapchain.deinit();

    const vert_shader_module = try api.ShaderModule.fromSourceFile(
        context,
        allocator,
        "shaders/shader.vert",
        .Vertex,
    );

    defer vert_shader_module.deinit();
    const frag_shader_module = try api.ShaderModule.fromSourceFile(
        context,
        allocator,
        "shaders/shader.frag",
        .Fragment,
    );
    defer frag_shader_module.deinit();

    const dynamic_states = [_]api.DynamicState{
        .viewport,
        .scissor,
    };

    test_tex = try api.Image.fromFile(context, allocator, "textures/shrek.png");
    errdefer test_tex.deinit();

    test_tex_view = try test_tex.createView(.{ .color_bit = true });
    errdefer test_tex_view.deinit();

    uniform_buffer = try UniformBuffer.create(context);
    errdefer uniform_buffer.deinit();

    test_descriptor = try api.Descriptor.init(context, allocator, .{ .bindings = &.{ .{
        .stages = .{ .vertex_bit = true },
        .data = .{ .Uniform = uniform_buffer.buffer() },
    }, .{
        .stages = .{ .fragment_bit = true },
        .data = .{ .Sampler = .{
            .view = test_tex_view.h_view,
            .sampler = try test_tex.getSampler(.{}),
        } },
    } } });
    errdefer test_descriptor.deinit();

    root_log.debug("vertex stride: {d}", .{VertexBuffer.Description.vertex_desc.stride});

    var fixed_function_state = api.FixedFunctionState{};
    fixed_function_state.init_self(context, &.{
        .viewport = .{ .Swapchain = &swapchain },
        .dynamic_states = &dynamic_states,
        .deez_nuts = true,
        .vertex_binding = VertexBuffer.Description.vertex_desc,
        .vertex_attribs = VertexBuffer.Description.attrib_desc,
        .descriptors = &.{test_descriptor.h_desc_layout},
    });
    defer fixed_function_state.deinit();

    renderpass = try api.RenderPass.initAlloc(context, scratch, &.{
        .{
            .attachment = .{
                .format = swapchain.surface_format.format,
                .samples = .{ .@"1_bit" = true },
                .load_op = .clear,
                .store_op = .store,
                .stencil_load_op = .dont_care,
                .stencil_store_op = .dont_care,
                .initial_layout = .undefined,
                .final_layout = .present_src_khr,
            },
            .tipo = .Color,
        },
        .{
            .attachment = .{
                .format = try dev.findDepthFormat(),
                .samples = .{ .@"1_bit" = true },
                .load_op = .clear,
                .store_op = .dont_care,
                .stencil_load_op = .dont_care,
                .stencil_store_op = .dont_care,
                .initial_layout = .undefined,
                .final_layout = .depth_stencil_attachment_optimal,
            },
            .tipo = .Depth,
        },
    });
    errdefer renderpass.deinit();

    graphics_pipeline = try api.GraphicsPipeline.init(context, .{
        .renderpass = &renderpass,
        .fixed_functions = &fixed_function_state,
        .shader_stages = &.{ vert_shader_module, frag_shader_module },
    }, scratch);
    errdefer graphics_pipeline.deinit();

    depth_image = try api.DepthImage.init(context, swapchain.extent);
    errdefer depth_image.deinit();

    framebuffers = try api.FrameBuffer.initAlloc(context, allocator, .{
        .renderpass = &renderpass,
        .swapchain = &swapchain,
        .depth_view = depth_image.view.h_view,
    });
    errdefer framebuffers.deinit();

    // create a bunch of stupid synchronization objects and stuff
    // I didn't really integrate these into the wrapper structs cuz i kinda don't really
    // know where to put them
    render_finished_semaphore = try api.Semaphore.init(context);
    image_finished_semaphore = try api.Semaphore.init(context);
    present_finished_fence = try api.Fence.init(context, true);

    command_buffer = try api.CommandBuffer.init(context, .{
        .src_queue_family = .Graphics,
    });

    const vertex_data = [_]TestVertexInput{
        .{ .position = math.vec(.{ -0.5, 0.0, -0.5 }), .color = math.vec(.{ 1.0, 0.0, 0.0 }), .uv = math.vec(.{ 1.0, 0.0 }) },
        .{ .position = math.vec(.{ 0.5, 0.0, -0.5 }), .color = math.vec(.{ 0.0, 1.0, 0.0 }), .uv = math.vec(.{ 0.0, 0.0 }) },
        .{ .position = math.vec(.{ 0.5, 0.0, 0.5 }), .color = math.vec(.{ 0.0, 0.0, 1.0 }), .uv = math.vec(.{ 0.0, 1.0 }) },
        .{ .position = math.vec(.{ -0.5, 0.0, 0.5 }), .color = math.vec(.{ 1.0, 1.0, 1.0 }), .uv = math.vec(.{ 1.0, 1.0 }) },

        .{ .position = math.vec(.{ -0.5, 0.5, -0.5 }), .color = math.vec(.{ 1.0, 0.0, 0.0 }), .uv = math.vec(.{ 1.0, 0.0 }) },
        .{ .position = math.vec(.{ 0.5, 0.5, -0.5 }), .color = math.vec(.{ 0.0, 1.0, 0.0 }), .uv = math.vec(.{ 0.0, 0.0 }) },
        .{ .position = math.vec(.{ 0.5, 0.5, 0.5 }), .color = math.vec(.{ 0.0, 0.0, 1.0 }), .uv = math.vec(.{ 0.0, 1.0 }) },
        .{ .position = math.vec(.{ -0.5, 0.5, 0.5 }), .color = math.vec(.{ 1.0, 1.0, 1.0 }), .uv = math.vec(.{ 1.0, 1.0 }) },
    };

    vertex_buffer = VertexBuffer.create(context, vertex_data.len) catch |err| {
        root_log.err("Failed to initialize vertex buffer: {!}", .{err});
        return err;
    };

    vertex_buffer.setData(vertex_data[0..]) catch |err| {
        root_log.err("Failed to load vertex data: {!}", .{err});
        return err;
    };

    const index_data = [_]u16{ 0, 1, 2, 2, 3, 0, 4, 5, 6, 6, 7, 4 };

    index_buffer = IndexBuffer.create(context, index_data.len) catch |err| {
        root_log.err("Failed to initialize index buffer: {!}", .{err});
        return err;
    };

    index_buffer.setData(index_data[0..]) catch |err| {
        root_log.err("Failed to load index buffer data: {!}", .{err});
        return err;
    };

    test_uniforms = .{
        .model = math.Mat4.identity().rotateX(math.radians(45.0)),
        .projection = math.Mat4.perspective(
            math.radians(75.0),
            600.0 / 900.0,
            0.1,
            30.0,
        ),
        .view = math.Mat4.lookAt(
            math.vec(.{ 2.0, 2.0, 2.0 }),
            math.vec(.{ 0, 0, 0 }),
            math.Vec3.global_up,
        ),
    };
}

fn updateUniforms() !void {
    test_uniforms = .{
        .model = math.Mat4.identity().rotateY(
            math.radians(45.0) * @as(f32, @floatCast(glfw.getTime())),
        ),
        .projection = math.Mat4.perspective(
            math.radians(45.0),
            900.0 / 600.0,
            0.1,
            30.0,
        ),
        .view = math.Mat4.lookAt(
            math.vec(.{ 2.0, 2.0, 2.0 }),
            math.vec(.{ 0, 0, 0 }),
            math.Vec3.global_up,
        ),
    };

    try test_descriptor.update(0, &test_uniforms);
}

fn mainLoop() !void {
    try present_finished_fence.wait();
    try present_finished_fence.reset();

    _ = try swapchain.getNextImage(image_finished_semaphore.h_sem, null);

    try command_buffer.reset();

    try command_buffer.begin();
    renderpass.begin(&command_buffer, &framebuffers, swapchain.image_index);

    try updateUniforms();

    graphics_pipeline.bind(&command_buffer);

    vertex_buffer.bind(&command_buffer);
    index_buffer.bind(&command_buffer);
    test_descriptor.bind(&command_buffer, graphics_pipeline.h_pipeline_layout, .{});

    dev.drawIndexed(&command_buffer, @intCast(index_buffer.buf.size), 1, 0, 0, 0);

    renderpass.end(&command_buffer);

    try command_buffer.end();

    try command_buffer.submit(.Graphics, .{
        .sem_sig = render_finished_semaphore.h_sem,
        .sem_wait = image_finished_semaphore.h_sem,
        .fence_wait = present_finished_fence.h_fence,
    });

    try context.presentFrame(&swapchain, .{
        .sem_wait = render_finished_semaphore.h_sem,
    });
}

fn deinit() void {
    dev.waitIdle() catch {
        root_log.err("Failed to wait on device", .{});
    };
    // destroy synchronization objects
    render_finished_semaphore.deinit();
    image_finished_semaphore.deinit();
    present_finished_fence.deinit();

    test_tex_view.deinit();
    test_tex.deinit();

    index_buffer.deinit();
    vertex_buffer.deinit();

    uniform_buffer.deinit();

    depth_image.deinit();
    framebuffers.deinit();
    graphics_pipeline.deinit();
    test_descriptor.deinit();
    renderpass.deinit();
    swapchain.deinit();
    context.deinit();
}

pub fn main() !void {
    var window = try helpers.makeBasicWindow(900, 600, "Test Window");
    defer glfw.terminate();
    defer window.destroy();

    glfw.vulkanSupported() catch |err| {
        std.log.err("Could not load Vulkan", .{});
        return err;
    };

    var gpa = std.heap.DebugAllocator(.{}).init;

    window.show();

    external_extensions = helpers.glfwInstanceExtensions();
    window_handle = &window;

    try init(gpa.allocator());
    defer deinit();

    while (!window.shouldClose()) {
        glfw.pollEvents();
        try mainLoop();
    }

    std.log.info("You win!\n", .{});
}
