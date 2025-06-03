const vk = @import("vulkan");
const std = @import("std");
const util = @import("../util.zig"); //TODO: avorelative id relative if possible

// =============================
// ******* Context API *********
// =============================

pub const VkInstance = vk.Instance;
pub const VkPfnVoidFunction = vk.PfnVoidFunction;

// type declarations and reimports
const BaseWrapper = vk.BaseWrapper;
const InstanceWrapper = vk.InstanceWrapper;
const DeviceWrapper = vk.DeviceWrapper;

// Proxies in this context refer to a pairing of a wrapper type and a corresponding Vulkan Handle
// (i.e InstanceProxy for InstanceWrapper). Wrapper functions are automatcally passed their paired handle object
// so this is really a convenience layer since so many vulkan API functions fall into the 3 wrapper families

const Allocator = std.mem.Allocator;


pub const GetProcAddrHandler = *const (fn (vk.Instance, [*:0] const u8) callconv(.c) vk.PfnVoidFunction);

pub const ContextConfig = struct {
    instance: struct {
        required_extensions: []const [*:0]const u8,
        validation_layers: []const [*:0]const u8,
    },

    device: struct {
        required_extensions: []const [*:0]const u8,
    },

    loader: GetProcAddrHandler,
    allocator: Allocator,
    enable_debug_log: bool,
};

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
// use a bunch of bullshit global state to test VkInstance creation
pub const Context = struct {

    pr_inst: vk.InstanceProxy,
    pr_dev: vk.DeviceProxy,

    h_dmsg: vk.DebugUtilsMessengerEXT,
    
    // API dispatch tables
    w_db: BaseWrapper,
    w_di: InstanceWrapper,
    w_dd: DeviceWrapper,



    fn defaultDebugConfig() vk.DebugUtilsMessengerCreateInfoEXT {
        return .{  
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
    } 

    fn createInstance(self: *Context, config: *const ContextConfig) !void {        

        // log the available extensions
        const available = self.w_db.enumerateInstanceExtensionPropertiesAlloc(null, config.allocator) catch {
            std.debug.print("Failed to enumerate extension properties... this is probably bad.\n", .{});
            return error.ExtensionEnumerationFailed;
        };

        std.debug.print("Available Extensions:\n", .{});
        for (available) |ext| {
            const en = util.asCString(&ext.extension_name);
            std.debug.print("Extension: {s}\n", .{en});
        }

        // make sure the requested validation layers are available
        const availableLayers = try self.w_db.enumerateInstanceLayerPropertiesAlloc(config.allocator);

        for (availableLayers) |*al| {
            const cLn = util.asCString(&al.layer_name);
            std.debug.print("Available Layer: {s}\n", .{cLn});
        }
        
        for (config.instance.validation_layers) |wl| {
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

        // TODO: Conditionally enable validation layers/logging based on config property
        // if (config.enable_debug_log) {
        // }

        // TODO: make sure our wanted extensions are available
    
        const instance = try self.w_db.createInstance(&.{
            .p_application_info = &.{
                .p_application_name = "RayEater_Renderer",
                .application_version = @bitCast(vk.makeApiVersion(0, 0, 0, 0)),
                .p_engine_name = "No Engine",
                .engine_version = @bitCast(vk.makeApiVersion(0, 0, 0, 0)),
                .api_version = @bitCast(vk.API_VERSION_1_4),
            },
            .p_next = &defaultDebugConfig(),
            .enabled_extension_count = @intCast(config.instance.required_extensions.len),
            .pp_enabled_extension_names = config.instance.required_extensions.ptr,
            .enabled_layer_count = @intCast(config.instance.validation_layers.len),
            .pp_enabled_layer_names = config.instance.validation_layers.ptr,
            .flags = .{.enumerate_portability_bit_khr = true},
        }, null);

        self.w_di = InstanceWrapper.load(instance, self.w_db.dispatch.vkGetInstanceProcAddr orelse return error.MissingDispatchFunc);

        self.pr_inst = vk.InstanceProxy.init(instance, &self.w_di);
    }

    fn createDebugMessenger(self: *Context) !void {
        self.h_dmsg = try self.pr_inst.createDebugUtilsMessengerEXT(&defaultDebugConfig(), null);
    }

    fn loadBase(self: *Context, config: *const ContextConfig) !void {
        self.w_db = BaseWrapper.load(config.loader);

        // check to see if the dispatch table loading fucked up
        if (self.w_db.dispatch.vkEnumerateInstanceExtensionProperties == null) {
            std.debug.print("Function loading failed (optional contains a null value)\n", .{});
            return error.DispatchLoadingFailed;
        }
    }

    pub fn init(config: *const ContextConfig) !Context {
        var ctx: Context = undefined;

        try ctx.loadBase(config);
        try ctx.createInstance(config);
        errdefer ctx.pr_inst.destroyInstance(null);

        try ctx.createDebugMessenger();
        
        return ctx;
    }

    pub fn deinit(self: *Context) void {
        self.pr_inst.destroyDebugUtilsMessengerEXT(
            self.h_dmsg,
            null,
        );

        self.pr_inst.destroyInstance(null);
    }
};

pub const Device = struct {

    pub fn init() !Device {
        
    } 
};
