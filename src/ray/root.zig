//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const api = @import("api/vulkan.zig");

// Another nasty import to keep extension names intact
const vk = @import("vulkan");

// NOTE: Temporary disgusting type exports in favor of slapping something together quicky
// please provide a custom loader function ASAP
pub const VkInstance = api.VkInstance;
pub const VkPfnVoidFunction = api.VkPfnVoidFunction;

const Allocator = std.mem.Allocator;

// use a bunch of bullshit global state to test VkInstance creation
pub const GetProcAddrHandler = *const (fn (vk.Instance, [*:0] const u8) callconv(.c) vk.PfnVoidFunction);

// vulkan loader function (i.e glfwGetProcAddress) in charge of finding vulkan API symbols in the first place
// (since all linking is of the runtime dynamic variety)
var loaderFunction: ?GetProcAddrHandler = null;

var externalExtensions: [][*:0]const u8 = undefined; 

var context: api.Context = undefined;

const validationLayers: [1][*:0]const u8 = .{"VK_LAYER_KHRONOS_validation"}; 




pub fn testInit(allocator: Allocator) !void {
    const loader = loaderFunction orelse return error.NoLoaderFunction;
    
    var extensions = std.ArrayList([*:0]const u8).init(allocator);
    defer extensions.deinit();

    try extensions.appendSlice(externalExtensions);
    try extensions.appendSlice(&[_][*:0]const u8{
        vk.extensions.khr_portability_enumeration.name,
        vk.extensions.khr_get_physical_device_properties_2.name,
        vk.extensions.ext_debug_utils.name,
    });

    context = try api.Context.init(&.{
        .loader = loader,
        .allocator = allocator,
        .instance = .{
            .required_extensions = @ptrCast(extensions.items[0..]),
            .validation_layers = &validationLayers,
        },
        .device = undefined,
        .enable_debug_log = true,
    });
}

pub fn setLoaderFunction(func: GetProcAddrHandler) void {
    loaderFunction = func;
}

pub fn setRequiredExtensions(names: [][*:0]const u8) void {
    externalExtensions = names;
}

pub fn testLoop() !void {
    
}



pub fn testDeinit() void {
    context.deinit();
} 

