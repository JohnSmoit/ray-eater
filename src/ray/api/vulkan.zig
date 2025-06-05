const vk = @import("vulkan");
const std = @import("std");
const util = @import("../util.zig"); //TODO: avorelative id relative if possible

// =============================
// ******* Context API *********
// =============================

pub const VkInstance = vk.Instance;
pub const VkPfnVoidFunction = vk.PfnVoidFunction;

// type declarations and reimports

// Proxies in this context refer to a pairing of a wrapper type and a corresponding Vulkan Handle
// (i.e InstanceProxy for InstanceWrapper). Wrapper functions are automatcally passed their paired handle object
// so this is really a convenience layer since so many vulkan API functions fall into the 3 wrapper families

const Allocator = std.mem.Allocator;

pub const GetProcAddrHandler = *const (fn (vk.Instance, [*:0]const u8) callconv(.c) vk.PfnVoidFunction);

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

fn debugCallback(message_severity: vk.DebugUtilsMessageSeverityFlagsEXT, message_type: vk.DebugUtilsMessageTypeFlagsEXT, p_callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT, p_user_data: ?*anyopaque) callconv(.c) vk.Bool32 {
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
    pr_inst: vk.InstanceProxy = undefined,

    h_dmsg: vk.DebugUtilsMessengerEXT = .null_handle,

    // API dispatch tables

    w_db: vk.BaseWrapper = undefined,
    w_di: vk.InstanceWrapper = undefined,

    // for some reason if I remove this field, the program builds but segfaults when the deinit function is called,
    // This is despite the fact that I do not reference this field at all anywhere...
    // Baby's first compiler bug? -- Will look into this later...
    w_dd: vk.DeviceWrapper = undefined, // I think I may have discovered a compiler bug relating to this field
    //temporary global allocator used for all object instantiation
    allocator: Allocator = undefined,

    dev: Device = undefined,

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
        const available = self.w_db.enumerateInstanceExtensionPropertiesAlloc(
            null,
            config.allocator,
        ) catch {
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
            .flags = .{ .enumerate_portability_bit_khr = true },
        }, null);

        self.w_di = vk.InstanceWrapper.load(
            instance,
            self.w_db.dispatch.vkGetInstanceProcAddr orelse
                return error.MissingDispatchFunc,
        );

        self.pr_inst = vk.InstanceProxy.init(instance, &self.w_di);
    }

    fn createDebugMessenger(self: *Context) !void {
        self.h_dmsg = try self.pr_inst.createDebugUtilsMessengerEXT(
            &defaultDebugConfig(),
            null,
        );
    }

    fn loadBase(self: *Context, config: *const ContextConfig) !void {
        self.w_db = vk.BaseWrapper.load(config.loader);

        // check to see if the dispatch table loading fucked up
        if (self.w_db.dispatch.vkEnumerateInstanceExtensionProperties == null) {
            std.debug.print("Function loading failed (optional contains a null value)\n", .{});
            return error.DispatchLoadingFailed;
        }
    }

    pub fn init(config: *const ContextConfig) !Context {
        var ctx: Context = .{
            .allocator = config.allocator,
        };

        try ctx.loadBase(config);
        try ctx.createInstance(config);
        errdefer ctx.pr_inst.destroyInstance(null);

        try ctx.createDebugMessenger();
        errdefer ctx.pr_inst.destroyDebugUtilsMessengerEXT(ctx.h_dmsg, null);

        ctx.dev = try Device.init(&ctx);
        errdefer ctx.dev.deinit();

        return ctx;
    }

    pub fn deinit(self: *Context) void {
        self.dev.deinit();

        self.pr_inst.destroyDebugUtilsMessengerEXT(
            self.h_dmsg,
            null,
        );

        self.pr_inst.destroyInstance(null);
    }
};

pub const Device = struct {
    const FamilyIndices = struct {
        graphics_family: ?u32,
        present_family: ?u32,
    };

    ctx: *const Context,
    families: FamilyIndices,

    h_dev: vk.Device,
    pr_dev: vk.DeviceProxy,
    dev_wrapper: *vk.DeviceWrapper,

    fn getQueueFamilies(
        dev: vk.PhysicalDevice,
        pr_inst: *const vk.InstanceProxy,
        allocator: Allocator,
    ) FamilyIndices {
        var found_indices: FamilyIndices = .{
            .graphics_family = null,
            .present_family = null,
        };

        const dev_queue_family_props =
            pr_inst.getPhysicalDeviceQueueFamilyPropertiesAlloc(
                dev,
                allocator,
            ) catch {
                return found_indices;
            };

        for (dev_queue_family_props, 0..) |props, index| {
            if (props.queue_flags.contains(.{
                .graphics_bit = true,
            })) {
                found_indices.graphics_family = @intCast(index);
            }

            //TODO: query for present-compatible queues as well
        }

        return found_indices;
    }

    fn pickSuitablePhysicalDevice(
        pr_inst: *const vk.InstanceProxy,
        allocator: Allocator,
    ) ?vk.PhysicalDevice {
        const physical_devices =
            pr_inst.enumeratePhysicalDevicesAlloc(allocator) catch |err| {
                std.debug.print(
                    "[DEVICE]: Encountered Error enumerating available physical devices: {!}\n",
                    .{err},
                );
                return null;
            };

        var chosen_dev: ?vk.PhysicalDevice = null;
        for (physical_devices) |dev| {
            const dev_properties = pr_inst.getPhysicalDeviceProperties(dev);
            std.debug.print(
                \\[DEVICE]: Found Device Named {s}
                \\    ID: {d}
                \\    Type: {d} 
                \\
            , .{ dev_properties.device_name, dev_properties.device_id, dev_properties.device_type });

            const dev_queue_indices = getQueueFamilies(dev, pr_inst, allocator);

            if (dev_queue_indices.graphics_family != null) {
                std.debug.print("[DEVICE]: Chose device named {s}\n", .{dev_properties.device_name});
                chosen_dev = dev;

                break;
            }
        }

        return chosen_dev;
    }

    // Later on, I plan to accept a device properties struct
    // which shall serve as the criteria for choosing a graphics unit
    pub fn init(parent: *const Context) !Device {
        // attempt to find a suitable device -- hardcoded for now
        const chosen_dev = pickSuitablePhysicalDevice(
            &parent.pr_inst,
            parent.allocator,
        ) orelse {
            std.debug.print("[DEVICE]: Failed to find suitable device\n", .{});
            return error.NoSuitableDevice;
        };

        const dev_queue_indices = getQueueFamilies(
            chosen_dev,
            &parent.pr_inst,
            parent.allocator,
        );

        // just enable all the available features lmao
        const dev_features = parent.pr_inst.getPhysicalDeviceFeatures(chosen_dev);

        const queue_create_infos = [_]vk.DeviceQueueCreateInfo{
            .{
                .queue_family_index = dev_queue_indices.graphics_family.?,
                .queue_count = 1,
                .p_queue_priorities = &[_]f32{1.0},
            },
        };

        const logical_dev = parent.pr_inst.createDevice(chosen_dev, &.{
            .p_queue_create_infos = &queue_create_infos,
            .queue_create_info_count = 1,
            .p_enabled_features = @ptrCast(&dev_features),
        }, null) catch |err| {
            std.debug.print("[DEVICE]: Failed to initialize logical device: {!}\n", .{err});
            return error.LogicalDeviceFailed;
        };

        // create zig wrapper bindings for the new logical device
        const dev_wrapper = try parent.allocator.create(vk.DeviceWrapper);
        errdefer parent.allocator.destroy(dev_wrapper);

        dev_wrapper.* = vk.DeviceWrapper.load(
            logical_dev,
            parent.w_di.dispatch.vkGetDeviceProcAddr.?,
        );

        const dev_proxy = vk.DeviceProxy.init(logical_dev, dev_wrapper);

        return Device{
            .ctx = parent,
            .dev_wrapper = dev_wrapper,
            .pr_dev = dev_proxy,
            .h_dev = logical_dev,
            .families = dev_queue_indices,
        };
    }

    pub fn deinit(self: *Device) void {
        self.pr_dev.destroyDevice(null);

        std.debug.print("[DEVICE]: Dispatch table address: {*}\n", .{self.dev_wrapper});
        self.ctx.allocator.destroy(self.dev_wrapper);
    }
};
