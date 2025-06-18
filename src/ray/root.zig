//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const api = @import("api/vulkan.zig");
const util = @import("util.zig");

const shader = @import("api/shader.zig");
const buffer = @import("api/buffer.zig");
const meth = @import("math.zig");

const vb = @import("api/vertex_buffer.zig");
const ib = @import("api/index_buffer.zig");
const ub = @import("api/uniform.zig");

// Another nasty import to keep extension names intact
const vk = @import("vulkan");
const glfw = @import("glfw");

// NOTE: Temporary disgusting type exports in favor of slapping something together quicky
// please provide a custom loader function ASAP
pub const VkInstance = api.VkInstance;
pub const VkPfnVoidFunction = api.VkPfnVoidFunction;

const Allocator = std.mem.Allocator;

// use a bunch of bullshit global state to test VkInstance creation
pub const GetProcAddrHandler = *const (fn (vk.Instance, [*:0]const u8) callconv(.c) vk.PfnVoidFunction);

const root_log = std.log.scoped(.root);
const glfw_log = std.log.scoped(.glfw);

// vulkan loader function (i.e glfwGetProcAddress) in charge of finding vulkan API symbols in the first place
// (since all linking is of the runtime dynamic variety)

var external_extensions: ?[][*:0]const u8 = null;

// temporary global vulkan state objects, most of which will be my wrapper types
var context: api.Context = undefined;
var device: api.Device = undefined;
var surface: api.Surface = undefined;

var graphics_queue: api.GraphicsQueue = undefined;
var present_queue: api.PresentQueue = undefined;
var swapchain: api.Swapchain = undefined;

var window_handle: ?*glfw.Window = null;

var renderpass: api.RenderPass = undefined;

var graphics_pipeline: api.GraphicsPipeline = undefined;

// rendering stuff
var framebuffers: api.FrameBufferSet = undefined;
var command_buffer: api.CommandBufferSet = undefined;

const validation_layers: [1][*:0]const u8 = .{"VK_LAYER_KHRONOS_validation"};
const device_extensions = [_][*:0]const u8{vk.extensions.khr_swapchain.name};

var render_finished_semaphore: vk.Semaphore = .null_handle;
var image_finished_semaphore: vk.Semaphore = .null_handle;
var present_finished_fence: vk.Fence = .null_handle;

const TestVertexInput = extern struct {
    position: meth.Vec2,
    color: meth.Vec3,
};

const VertexBuffer = vb.VertexBuffer(TestVertexInput);
const IndexBuffer = ib.IndexBuffer(u16);

var vertex_buffer: VertexBuffer = undefined;
var index_buffer: IndexBuffer = undefined;

var vb_interface: buffer.AnyBuffer = undefined;
var ib_interface: buffer.AnyBuffer = undefined;

fn glfwErrorCallback(code: c_int, desc: [*c]const u8) callconv(.c) void {
    glfw_log.err("error code {d} -- Message: {s}", .{ code, desc });
}

pub fn testInit(allocator: Allocator) !void {
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
        vk.extensions.khr_portability_enumeration.name,
        vk.extensions.khr_get_physical_device_properties_2.name,
        vk.extensions.ext_debug_utils.name,
    });

    context = try api.Context.init(&.{
        .loader = glfw.glfwGetInstanceProcAddress,
        .allocator = allocator,
        .instance = .{
            .required_extensions = @ptrCast(extensions.items[0..]),
            .validation_layers = &validation_layers,
        },
        .device = undefined,
        .enable_debug_log = true,
        .window = window_handle orelse {
            return error.NoWindowSpecified;
        },
    });
    errdefer context.deinit();

    surface = try api.Surface.init(window_handle.?, &context);
    errdefer surface.deinit();

    device = try api.Device.init(&context, &.{
        .surface = &surface,
        .required_extensions = &device_extensions,
    });
    errdefer device.deinit();

    graphics_queue = try api.GraphicsQueue.init(&device);
    errdefer graphics_queue.deinit();

    present_queue = try api.PresentQueue.init(&device);
    errdefer present_queue.deinit();

    swapchain = try api.Swapchain.init(&device, &surface, &.{
        .requested_present_mode = .mailbox_khr,
        .requested_format = .{
            .color_space = .srgb_nonlinear_khr,
            .format = .b8g8r8a8_srgb,
        },
        .requested_extent = .{
            .width = 900, // hardcoded for my sanity
            .height = 600,
        },
    });
    errdefer swapchain.deinit();

    // test create shader modules and stuff
    const vert_shader_module = try shader.Module.from_source_file(
        .Vertex,
        "shaders/shader.vert",
        &device,
    );
    defer vert_shader_module.deinit();
    const frag_shader_module = try shader.Module.from_source_file(
        .Fragment,
        "shaders/shader.frag",
        &device,
    );
    defer frag_shader_module.deinit();

    // test create fixed function pipeline state
    const dynamic_states = [_]vk.DynamicState{
        .viewport,
        .scissor,
    };

    var fixed_function_state = api.FixedFunctionState{};
    fixed_function_state.init_self(&device, &.{
        .viewport = .{ .Swapchain = &swapchain },
        .dynamic_states = &dynamic_states,
        .deez_nuts = true,
        .vertex_binding = VertexBuffer.Description.vertex_desc,
        .vertex_attribs = VertexBuffer.Description.attrib_desc,
    });
    defer fixed_function_state.deinit();

    // test create render pass state and stuff i guess
    renderpass = try api.RenderPass.initFromSwapchain(&device, &swapchain);
    errdefer renderpass.deinit();

    graphics_pipeline = try api.GraphicsPipeline.init(&device, &.{
        .renderpass = &renderpass,
        .fixed_functions = &fixed_function_state,
        .shader_stages = &[_]shader.Module{ vert_shader_module, frag_shader_module },
    }, scratch);
    errdefer graphics_pipeline.deinit();

    framebuffers = try api.FrameBufferSet.initAlloc(&device, allocator, &.{
        .renderpass = &renderpass,
        .image_views = swapchain.images,
        .extent = vk.Rect2D{
            .extent = swapchain.extent,
            .offset = .{ .x = 0, .y = 0 },
        },
    });
    errdefer framebuffers.deinit();

    // create a bunch of stupid synchronization objects and stuff
    // I didn't really integrate these into the wrapper structs cuz i kinda don't really
    // know where to put them
    render_finished_semaphore = try device.pr_dev.createSemaphore(&.{}, null);
    image_finished_semaphore = try device.pr_dev.createSemaphore(&.{}, null);
    present_finished_fence = try device.pr_dev.createFence(&.{
        .flags = .{ .signaled_bit = true },
    }, null);

    command_buffer = try api.CommandBufferSet.init(&device);

    // test vertex data and stuff
    const vertex_data = [_]TestVertexInput{
        .{ .position = meth.vec(.{ -0.5, -0.5 }), .color = meth.vec(.{ 1.0, 0.0, 0.0 }) },
        .{ .position = meth.vec(.{ 0.5, -0.5 }), .color = meth.vec(.{ 0.0, 1.0, 0.0 }) },
        .{ .position = meth.vec(.{ 0.5, 0.5 }), .color = meth.vec(.{ 0.0, 0.0, 1.0 }) },
        .{ .position = meth.vec(.{ -0.5, 0.5 }), .color = meth.vec(.{ 1.0, 1.0, 1.0 }) },
    };

    vertex_buffer = VertexBuffer.create(&device, vertex_data.len) catch |err| {
        root_log.err("Failed to initialize vertex buffer: {!}", .{err});
        return err;
    };
    // TODO: Interface casting shouldn't be required to use basic member functions lol
    // This literally sucks ass I don't care how cursed the implementation is,
    // it should not require this
    vb_interface = vertex_buffer.buffer();
    errdefer vb_interface.deinit();

    vb_interface.setData(vertex_data[0..]) catch |err| {
        root_log.err("Failed to load vertex data: {!}", .{err});
        return err;
    };

    const index_data = [_]u16{ 0, 1, 2, 2, 3, 0 };

    index_buffer = IndexBuffer.create(&device, index_data.len) catch |err| {
        root_log.err("Failed to initialize index buffer: {!}", .{err});
        return err;
    };

    ib_interface = index_buffer.buffer();
    errdefer ib_interface.deinit();

    ib_interface.setData(index_data[0..]) catch |err| {
        root_log.err("Failed to load index buffer data: {!}", .{err});
        return err;
    };
}

pub fn setWindow(window: *glfw.Window) void {
    window_handle = window;
}

pub fn setRequiredExtensions(names: [][*:0]const u8) void {
    external_extensions = names;
}

pub fn testLoop() !void {
    _ = device.pr_dev.waitForFences(
        1,
        util.asManyPtr(vk.Fence, &present_finished_fence),
        vk.TRUE,
        std.math.maxInt(u64),
    ) catch {}; // fuck rendering errors

    device.pr_dev.resetFences(
        1,
        util.asManyPtr(vk.Fence, &present_finished_fence),
    ) catch {};

    const current_image = try swapchain.getNextImage(image_finished_semaphore, null);

    try command_buffer.reset();

    try command_buffer.begin();
    renderpass.begin(&command_buffer, &framebuffers, current_image);

    graphics_pipeline.bind(&command_buffer);

    vb_interface.bind(&command_buffer);
    ib_interface.bind(&command_buffer);

    device.drawIndexed(&command_buffer, 6, 1, 0, 0, 0);

    renderpass.end(&command_buffer);

    try command_buffer.end();

    try graphics_queue.submit(
        &command_buffer,
        image_finished_semaphore,
        render_finished_semaphore,
        present_finished_fence,
    );

    try present_queue.present(
        &swapchain,
        current_image,
        render_finished_semaphore,
    );
}

pub fn testDeinit() void {
    device.waitIdle() catch {
        root_log.err("Failed to wait on device", .{});
    };
    // destroy synchronization objects
    device.pr_dev.destroySemaphore(render_finished_semaphore, null);
    device.pr_dev.destroySemaphore(image_finished_semaphore, null);
    device.pr_dev.destroyFence(present_finished_fence, null);

    ib_interface.deinit();
    vb_interface.deinit();
    framebuffers.deinit();
    graphics_pipeline.deinit();
    renderpass.deinit();
    swapchain.deinit();
    graphics_queue.deinit();
    present_queue.deinit();
    surface.deinit();
    device.deinit();
    context.deinit();
}
