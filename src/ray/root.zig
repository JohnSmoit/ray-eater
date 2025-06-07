//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const api = @import("api/vulkan.zig");

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

// vulkan loader function (i.e glfwGetProcAddress) in charge of finding vulkan API symbols in the first place
// (since all linking is of the runtime dynamic variety)

var external_extensions: ?[][*:0]const u8 = null;

var context: api.Context = undefined;
var device: api.Device = undefined;
var surface: api.Surface = undefined;

var graphics_queue: api.GraphicsQueue = undefined;
var present_queue: api.PresentQueue = undefined;

var window_handle: ?*glfw.Window = null;

const validation_layers: [1][*:0]const u8 = .{"VK_LAYER_KHRONOS_validation"};
const device_extensions = [_][*:0]const u8{vk.extensions.khr_swapchain.name};

pub fn testInit(allocator: Allocator) !void {
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
}

pub fn setWindow(window: *glfw.Window) void {
    window_handle = window;
}

pub fn setRequiredExtensions(names: [][*:0]const u8) void {
    external_extensions = names;
}

pub fn testLoop() !void {}

pub fn testDeinit() void {
    graphics_queue.deinit();
    present_queue.deinit();
    surface.deinit();
    device.deinit();
    context.deinit();
}
