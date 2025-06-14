//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const api = @import("api/vulkan.zig");
const shader = @import("api/shader.zig");

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

const root_log = std.log;
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

const validation_layers: [1][*:0]const u8 = .{"VK_LAYER_KHRONOS_validation"};
const device_extensions = [_][*:0]const u8{vk.extensions.khr_swapchain.name};

fn glfwErrorCallback(code: c_int, desc: [*c]const u8) callconv(.c) void {
    glfw_log.err("error code {d} -- Message: {s}", .{ code, desc });
}

pub fn testInit(allocator: Allocator) !void {
    _ = glfw.setErrorCallback(glfwErrorCallback);

    // scratch (Arena) allocator for memory stuff
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
    });
    defer fixed_function_state.deinit();

    // test create render pass state and stuff i guess
    renderpass = try api.RenderPass.init_from_swapchain(&device, &swapchain);
    errdefer renderpass.deinit();

    graphics_pipeline = try api.GraphicsPipeline.init(&device, &.{
        .renderpass = &renderpass,
        .fixed_functions = &fixed_function_state,
        .shader_stages = &[_]shader.Module{ vert_shader_module, frag_shader_module },
    }, scratch);
    errdefer graphics_pipeline.deinit();
}

pub fn setWindow(window: *glfw.Window) void {
    window_handle = window;
}

pub fn setRequiredExtensions(names: [][*:0]const u8) void {
    external_extensions = names;
}

pub fn testLoop() !void {}

pub fn testDeinit() void {
    graphics_pipeline.deinit();
    renderpass.deinit();
    swapchain.deinit();
    graphics_queue.deinit();
    present_queue.deinit();
    surface.deinit();
    device.deinit();
    context.deinit();
}
