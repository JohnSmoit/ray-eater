//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const vk = @import("vulkan");

// NOTE: Temporary disgusting type exports in favor of slapping something together quicky
// please provide a custom loader function ASAP
pub const VkInstance = vk.Instance;
pub const VkPfnVoidFunction = vk.PfnVoidFunction;

// type declarations and reimports
const BaseWrapper = vk.BaseWrapper;
const InstanceWrapper = vk.InstanceWrapper;
const DeviceWrapper = vk.DeviceWrapper;

// Proxies in this context refer to a pairing of a wrapper type and a corresponding Vulkan Handle
// (i.e InstanceProxy for InstanceWrapper). Wrapper functions are automatcally passed their paired handle object
// so this is really a convenience layer since so many vulkan API functions fall into the 3 wrapper families
const Instance = vk.InstanceProxy;
const Device = vk.DeviceProxy;

const Allocator = std.mem.Allocator;

// use a bunch of bullshit global state to test VkInstance creation
pub const GetProcAddrHandler = *const (fn (vk.Instance, [*:0] const u8) callconv(.c) vk.PfnVoidFunction);


// vulkan-bindings base dispatch table along with ziggified wrapper functions
// note that base wrapper refers to vulkan API calls that don't require Instance data (i.e no VkInstance or VkDevice)
var vkb: BaseWrapper = undefined;

// vulkan-bindings instance dispatch table along with ziggified wrapper functions
// note that instance refers to vulkan API calls that require a VkInstance to be passed 
// Generally, these are API calls that operate on VkInstances or require a VkInstance to be supplied to another Vulkan Object
var vki: InstanceWrapper = undefined;

// vulkan-bindings device dispatch table along with ziggified wrapper functions
// note that instance refers to vulkan API calls that require a VkDevice to be passed 
// Generally, these are API calls that operate on VkDevices or require a VkDevice to be supplied to another Vulkan Object
var vkd: DeviceWrapper = undefined;

// vulkan loader function (i.e glfwGetProcAddress) in charge of finding vulkan API symbols in the first place
// (since all linking is of the runtime dynamic variety)
var loaderFunction: ?GetProcAddrHandler = null;

var dev: Device = undefined;
var inst: Instance = undefined;

var externalExtensions: [][*:0]const u8 = undefined; 

const validationLayers: [1][*:0]const u8 = .{"VK_LAYER_KHRONOS_validation"}; 

var debugMessenger: vk.DebugUtilsMessengerEXT = undefined;

fn asCString(rep: anytype) [*:0]const u8 {
    return @as([*:0]const u8, @ptrCast(rep));
}

fn checkValidationLayerSupport(allocator: Allocator) !void {
    const availableLayers = try vkb.enumerateInstanceLayerPropertiesAlloc(allocator);

    for (availableLayers) |*al| {
        const cLn = asCString(&al.layer_name);
        std.debug.print("Available Layer: {s}\n", .{cLn});
    }
    
    for (validationLayers) |wl| {
        var found = false;

        for (availableLayers) |*al| {
            if (std.mem.orderZ(u8, wl, @as([*:0]const u8, @ptrCast(&al.layer_name))) == .eq) {
                found = true;
            }
        }

        if (!found) {
            return error.MissingValidationLayer;
        }
    }
}



fn createInstance(allocator: Allocator, info: *const vk.DebugUtilsMessengerCreateInfoEXT) !void {
    var reqExtensionNames = std.ArrayList([*:0]const u8).init(allocator);
    defer reqExtensionNames.deinit();

    try reqExtensionNames.appendSlice(@ptrCast(externalExtensions));
    
    // MACOS compatability extensions
    try reqExtensionNames.append(vk.extensions.khr_portability_enumeration.name);
    try reqExtensionNames.append(vk.extensions.khr_get_physical_device_properties_2.name);

    // debug because lord knows there will be bugz
    try reqExtensionNames.append(vk.extensions.ext_debug_utils.name);

    for (reqExtensionNames.items) |item| {
        std.debug.print("Extension Wanted: {s}\n", .{item});
    }

    // check that our neccesary (for my sanity) validation layers are available for use
    // and enable them if they are.
    try checkValidationLayerSupport(allocator);


    const instance = try vkb.createInstance(&.{
        .p_application_info = &.{
            .p_application_name = "RayEater_Renderer",
            .application_version = @bitCast(vk.makeApiVersion(0, 0, 0, 0)),
            .p_engine_name = "No Engine",
            .engine_version = @bitCast(vk.makeApiVersion(0, 0, 0, 0)),
            .api_version = @bitCast(vk.API_VERSION_1_4),
        },
        .p_next = info,
        .enabled_extension_count = @intCast(reqExtensionNames.items.len),
        .pp_enabled_extension_names = reqExtensionNames.items.ptr,
        .enabled_layer_count = @intCast(validationLayers.len),
        .pp_enabled_layer_names = &validationLayers,
        .flags = .{.enumerate_portability_bit_khr = true},
    }, null);

    vki = InstanceWrapper.load(instance, vkb.dispatch.vkGetInstanceProcAddr orelse return error.MissingDispatchFunc);

    inst = Instance.init(instance, &vki);
}

// yummy raw vulkan cuz I don't think the provided wrappers include debug extensions and such

fn debugCallback(
    message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
    message_type: vk.DebugUtilsMessageTypeFlagsEXT,
    p_callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT,
    p_user_data: ?*anyopaque
) callconv(.c) vk.Bool32 {
    const callbackData = p_callback_data orelse {
        std.debug.print("Something probably bad happened but vulkan won't fucking give me the info\n", .{});
        return vk.FALSE;
    };

    std.debug.print("[VALIDATION]: {s}\n", .{callbackData.p_message orelse "Fuck"});

    _ = message_severity;
    _ = message_type;
    _ = p_user_data;

    return vk.FALSE;
}

fn initDebugMessenger(instance: vk.Instance, info: *const vk.DebugUtilsMessengerCreateInfoEXT) !void {
    const func = vkb.getInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT") orelse return error.MessengerCreateFuncMissing;
    const casted: vk.PfnCreateDebugUtilsMessengerEXT = @ptrCast(func);
    

    if (casted(instance, info, null, &debugMessenger) != vk.Result.success) {
        return error.CreateMessengerFailed;
    }

}

pub fn testInit(allocator: Allocator) !void {
    const loader = loaderFunction orelse return error.NoLoaderFunction;

    vkb = BaseWrapper.load(loader);

    // check to see if the dispatch table loading fucked up
    if (vkb.dispatch.vkEnumerateInstanceExtensionProperties == null) {
        std.debug.print("Function loading failed (optional contains a null value)\n", .{});
        return error.DispatchLoadingFailed;
    }

    const available = vkb.enumerateInstanceExtensionPropertiesAlloc(null, allocator) catch {
        std.debug.print("Failed to enumerate extension properties... this is probably bad.\n", .{});
        return error.ExtensionEnumerationFailed;
    };

    std.debug.print("Available Extensions:\n", .{});
    for (available) |ext| {
        const en = asCString(&ext.extension_name);
        std.debug.print("Extension: {s}\n", .{en});
    }

    const info: vk.DebugUtilsMessengerCreateInfoEXT = .{
        .s_type = vk.StructureType.debug_utils_messenger_create_info_ext,
        .message_severity = .{
            .verbose_bit_ext = true,
            .warning_bit_ext = true,
            .error_bit_ext = true,
        },
        .message_type = .{
            .general_bit_ext = true,
            .validation_bit_ext = true,
            .performance_bit_ext = true,
        },
        .pfn_user_callback = debugCallback,
    };
    
    try createInstance(allocator, &info);
    try initDebugMessenger(inst.handle, &info);
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
    // too lazy to type out a raw vulkan debug messenger destroy function so enjoy a resource leak.
    inst.destroyInstance(null);

} 

