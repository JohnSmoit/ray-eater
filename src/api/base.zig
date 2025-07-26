//! Vulkan base types baked into an application's context

const vk = @import("vulkan");
const std = @import("std");
const glfw = @import("glfw");
const util = @import("../util.zig");
const api = @import("api.zig");

const Allocator = std.mem.Allocator;

const QueueType = api.QueueType;
const Queue = api.ComputeQueue;
const CommandBuffer = @import("command_buffer.zig");

pub const GetProcAddrHandler = *const (fn (
    vk.Instance,
    [*:0]const u8,
) callconv(.c) vk.PfnVoidFunction);

const validation_log = std.log.scoped(.validation);

fn debugCallback(
    message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
    message_type: vk.DebugUtilsMessageTypeFlagsEXT,
    p_callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT,
    p_user_data: ?*anyopaque,
) callconv(.c) vk.Bool32 {
    const callback_data = p_callback_data orelse {
        validation_log.err(
            "Something probably bad happened but vulkan won't fucking give me the info",
            .{},
        );
        return vk.FALSE;
    };

    // TODO: Handle the bitset flags as independent enum values...
    // That way, logging levels will work for vulkan validation as well..
    const msg_level = message_severity.toInt();

    validation_log.debug(
        "{d} -- {s}",
        .{ msg_level, callback_data.p_message orelse "Fuck" },
    );

    _ = message_type;
    _ = p_user_data;

    return vk.FALSE;
}

//TODO: Yeet into a non-owning view of the context
pub const InstanceHandler = struct {
    pub const Config = struct {
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
    pub const log = std.log.scoped(.instance);
    pr_inst: vk.InstanceProxy = undefined,

    h_dmsg: vk.DebugUtilsMessengerEXT = .null_handle,

    // API dispatch tables

    w_db: vk.BaseWrapper = undefined,
    w_di: *vk.InstanceWrapper = undefined,

    // for some reason if I remove this field, the program builds but segfaults when the deinit function is called,
    // This is despite the fact that I do not reference this field at all anywhere...
    // Baby's first compiler bug? -- Will look into this later...
    //temporary global allocator used for all object instantiation
    // Further investigation makes me think this is some weird asfuck case of undefined behavior
    allocator: Allocator = undefined,

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

    fn createInstance(self: *InstanceHandler, config: *const Config) !void {

        // log the available extensions
        const available = self.w_db.enumerateInstanceExtensionPropertiesAlloc(
            null,
            config.allocator,
        ) catch {
            log.debug("Failed to enumerate extension properties... this is probably bad.\n", .{});
            return error.ExtensionEnumerationFailed;
        };
        defer config.allocator.free(available);

        log.debug("Available Extensions:", .{});
        for (available) |ext| {
            const en = util.asCString(&ext.extension_name);
            log.debug("Extension: {s}", .{en});
        }

        for (config.instance.required_extensions) |req| {
            log.debug("Required -- {s}", .{req});
        }

        // make sure the requested validation layers are available
        const availableLayers = try self.w_db.enumerateInstanceLayerPropertiesAlloc(config.allocator);
        defer config.allocator.free(availableLayers);

        for (availableLayers) |*al| {
            const cLn = util.asCString(&al.layer_name);
            log.debug("Available Layer: {s}", .{cLn});
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

        self.w_di = try self.allocator.create(vk.InstanceWrapper);
        errdefer self.allocator.destroy(self.w_di);

        self.w_di.* = vk.InstanceWrapper.load(
            instance,
            self.w_db.dispatch.vkGetInstanceProcAddr orelse
                return error.MissingDispatchFunc,
        );

        // self.w_di = instance_wrapper;
        log.debug("Is dispatch entry null: {s}", .{
            if (self.w_di.dispatch.vkDestroyDebugUtilsMessengerEXT != null) "no" else "yes",
        });
        self.pr_inst = vk.InstanceProxy.init(instance, self.w_di);
    }

    fn createDebugMessenger(self: *InstanceHandler) !void {
        self.h_dmsg = try self.pr_inst.createDebugUtilsMessengerEXT(
            &defaultDebugConfig(),
            null,
        );
    }

    fn loadBase(self: *InstanceHandler, config: *const Config) !void {
        self.w_db = vk.BaseWrapper.load(config.loader);

        // check to see if the dispatch table loading fucked up
        if (self.w_db.dispatch.vkEnumerateInstanceExtensionProperties == null) {
            log.debug("Function loading failed (optional contains a null value)", .{});
            return error.DispatchLoadingFailed;
        }
    }

    pub fn init(config: *const Config) !InstanceHandler {
        var ctx: InstanceHandler = .{
            .allocator = config.allocator,
        };

        try ctx.loadBase(config);
        try ctx.createInstance(config);
        errdefer ctx.pr_inst.destroyInstance(null);
        errdefer ctx.allocator.destroy(ctx.w_di);

        try ctx.createDebugMessenger();
        errdefer ctx.pr_inst.destroyDebugUtilsMessengerEXT(ctx.h_dmsg, null);

        return ctx;
    }

    pub fn deinit(self: *InstanceHandler) void {
        log.debug("Is dispatch entry null: {s}", .{
            if (self.pr_inst.wrapper.dispatch.vkDestroyDebugUtilsMessengerEXT != null) "no" else "yes",
        });

        self.pr_inst.destroyDebugUtilsMessengerEXT(
            self.h_dmsg,
            null,
        );

        self.pr_inst.destroyInstance(null);
        self.allocator.destroy(self.w_di);
    }
};

//TODO: Yeet into a non-owning view of context
pub const DeviceHandler = struct {
    pub const Config = struct {
        surface: *const SurfaceHandler,
        required_extensions: []const [*:0]const u8 = &[0][*:0]const u8{},
    };

    pub const log = std.log.scoped(.device);
    const FamilyIndices = struct {
        graphics_family: ?u32 = null,
        present_family: ?u32 = null,
        compute_family: ?u32 = null,
    };

    pub const SwapchainSupportDetails = struct {
        capabilities: vk.SurfaceCapabilitiesKHR = undefined,
        formats: []vk.SurfaceFormatKHR = util.emptySlice(vk.SurfaceFormatKHR),
        present_modes: []vk.PresentModeKHR = util.emptySlice(vk.PresentModeKHR),
        allocator: ?Allocator,

        pub fn deinit(self: *const SwapchainSupportDetails) void {
            const allocator = self.allocator orelse return;

            allocator.free(self.formats);
            allocator.free(self.present_modes);
        }
    };

    /// ## Brief
    /// deallocate everything returned from this function or I will murder you
    ///
    /// ## Other
    /// also, I just realized that I'm kinda doin bad zig practice by making deez allocations sorta
    /// implicit oops (Imma try and fix that later). TO be fair, all of this allocation shit
    /// is sort of temporary anyhoo, since DebugAllocator is obviously not the way to go in production
    pub fn getDeviceSupport(
        pr_inst: *const vk.InstanceProxy,
        surface: *const SurfaceHandler,
        pdev: vk.PhysicalDevice, //TODO: Optional -- Will use chosen physical device info if omitted
        allocator: Allocator,
    ) !SwapchainSupportDetails {
        const capabilities = try pr_inst.getPhysicalDeviceSurfaceCapabilitiesKHR(
            pdev,
            surface.h_surface,
        );
        const formats = pr_inst.getPhysicalDeviceSurfaceFormatsAllocKHR(
            pdev,
            surface.h_surface,
            allocator,
        ) catch util.emptySlice(vk.SurfaceFormatKHR);
        errdefer allocator.free(formats);

        const present_modes = pr_inst.getPhysicalDeviceSurfacePresentModesAllocKHR(
            pdev,
            surface.h_surface,
            allocator,
        ) catch util.emptySlice(vk.PresentModeKHR);
        errdefer allocator.free(present_modes);

        return .{
            .capabilities = capabilities,
            .formats = formats,
            .present_modes = present_modes,
            .allocator = allocator,
        };
    }

    pub fn findSupportedFormat(
        self: *const DeviceHandler,
        candidates: []const vk.Format,
        tiling: vk.ImageTiling,
        features: vk.FormatFeatureFlags,
    ) !vk.Format {
        for (candidates) |fmt| {
            const props = self.ctx.pr_inst.getPhysicalDeviceFormatProperties(self.h_pdev, fmt);

            const matches = switch (tiling) {
                .linear => props.linear_tiling_features.contains(features),
                .optimal => props.optimal_tiling_features.contains(features),
                else => return error.FormatNotSupported,
            };

            if (matches) {
                return fmt;
            }
        }

        return error.FormatNotSupported;
    }

    pub fn findDepthFormat(self: *const DeviceHandler) !vk.Format {
        return try self.findSupportedFormat(
            &[_]vk.Format{
                .d32_sfloat_s8_uint,
                .d24_unorm_s8_uint,
            },
            .optimal,
            .{ .depth_stencil_attachment_bit = true },
        );
    }

    ctx: *const InstanceHandler,

    // TODO: Support overlap in queue families
    // (i.e) some queues might support both compute and graphics operations
    families: FamilyIndices,
    swapchain_details: SwapchainSupportDetails,

    h_dev: vk.Device = .null_handle,
    h_pdev: vk.PhysicalDevice = .null_handle,

    pr_dev: vk.DeviceProxy,
    dev_wrapper: *vk.DeviceWrapper = undefined,

    // HAve the device context manage the command pool
    // and then all command buffers can be created using the same pool
    h_cmd_pool: vk.CommandPool = .null_handle,
    props: vk.PhysicalDeviceProperties,

    pub fn findMemoryTypeIndex(
        self: *const DeviceHandler,
        mem_reqs: vk.MemoryRequirements,
        req_flags: ?vk.MemoryPropertyFlags,
    ) !u32 {
        const dev_mem_props = self.getMemProperties();

        const requested_flags: vk.MemoryPropertyFlags = req_flags orelse .{};

        var found = false;
        var chosen_mem: u32 = 0;

        for (0..dev_mem_props.memory_type_count) |i| {
            const mem_flags = dev_mem_props.memory_types[i].property_flags;
            if (mem_reqs.memory_type_bits & (@as(u32, 1) << @intCast(i)) != 0 and mem_flags.contains(requested_flags)) {
                found = true;

                chosen_mem = @intCast(i);
                break;
            }
        }

        if (found)
            return chosen_mem;

        return error.IncompatibleMemoryTypes;
    }

    fn getQueueFamilies(
        dev: vk.PhysicalDevice,
        pr_inst: *const vk.InstanceProxy,
        surface: *const SurfaceHandler,
        allocator: Allocator,
    ) FamilyIndices {
        var found_indices: FamilyIndices = .{
            .graphics_family = null,
            .present_family = null,
            .compute_family = null,
        };

        const dev_queue_family_props =
            pr_inst.getPhysicalDeviceQueueFamilyPropertiesAlloc(
                dev,
                allocator,
            ) catch {
                return found_indices;
            };
        defer allocator.free(dev_queue_family_props);

        for (dev_queue_family_props, 0..) |props, index| {
            const i: u32 = @intCast(index);
            if (props.queue_flags.contains(.{
                .graphics_bit = true,
            })) {
                found_indices.graphics_family = i;
            }
            if (props.queue_flags.contains(.{
                .compute_bit = true,
            })) {
                found_indices.compute_family = i;
            }

            if ((pr_inst.getPhysicalDeviceSurfaceSupportKHR(
                dev,
                i,
                surface.h_surface,
            ) catch vk.FALSE) == vk.TRUE) {
                found_indices.present_family = i;
            }
        }

        return found_indices;
    }

    const DeviceCandidate = struct {
        dev: vk.PhysicalDevice,
        val: u32,
    };

    fn compareCandidates(ctx: void, a: DeviceCandidate, b: DeviceCandidate) std.math.Order {
        _ = ctx;
        return if (a.val < b.val) .lt else if (a.val > b.val) .gt else .eq;
    }

    //HACK: Since most modern GPUS are all but guarunteed to support what I'm doing,
    //I'm just going to pick the first discrete GPU and call it a day...
    // This will likely require a bit of upgrade when I consider making this project more portable
    fn pickSuitablePhysicalDevice(
        pr_inst: *const vk.InstanceProxy,
        config: *const Config,
        allocator: Allocator,
    ) ?vk.PhysicalDevice {
        const physical_devices =
            pr_inst.enumeratePhysicalDevicesAlloc(allocator) catch |err| {
                log.debug(
                    "Encountered Error enumerating available physical devices: {!}",
                    .{err},
                );
                return null;
            };
        defer allocator.free(physical_devices);

        for (physical_devices) |dev| {
            const props = pr_inst.getPhysicalDeviceProperties(dev);
            if (props.device_type == .discrete_gpu) {
                log.debug("Found suitable device named: {s}", .{props.device_name});
                return dev;
            }
        }

        _ = config;

        return null;
    }

    // Later on, I plan to accept a device properties struct
    // which shall serve as the criteria for choosing a graphics unit
    pub fn init(parent: *const InstanceHandler, config: *const Config) !DeviceHandler {
        // attempt to find a suitable device -- hardcoded for now
        const chosen_dev = pickSuitablePhysicalDevice(
            &parent.pr_inst,
            config,
            parent.allocator,
        ) orelse {
            log.debug("Failed to find suitable device\n", .{});
            return error.NoSuitableDevice;
        };

        const dev_properties = parent.pr_inst.getPhysicalDeviceProperties(chosen_dev);

        const dev_queue_indices = getQueueFamilies(
            chosen_dev,
            &parent.pr_inst,
            config.surface,
            parent.allocator,
        );

        // just enable all the available features lmao
        const dev_features = parent.pr_inst.getPhysicalDeviceFeatures(chosen_dev);
        const swapchain_details = getDeviceSupport(
            &parent.pr_inst,
            config.surface,
            chosen_dev,
            parent.allocator,
        ) catch unreachable;
        errdefer swapchain_details.deinit();

        const priority = [_]f32{1.0};

        // Hardcode dem queues, although obviously imma want some more configuration later on...
        const queue_create_infos = [_]vk.DeviceQueueCreateInfo{
            .{
                .queue_family_index = dev_queue_indices.graphics_family.?,
                .queue_count = 1,
                .p_queue_priorities = &priority,
            },
            .{
                .queue_family_index = dev_queue_indices.present_family.?,
                .queue_count = 1,
                .p_queue_priorities = &priority,
            },
        };

        const logical_dev = parent.pr_inst.createDevice(chosen_dev, &.{
            .p_queue_create_infos = &queue_create_infos,
            .queue_create_info_count = queue_create_infos.len,
            .p_enabled_features = @ptrCast(&dev_features),
            .pp_enabled_extension_names = config.required_extensions.ptr,
            .enabled_extension_count = @intCast(config.required_extensions.len),
        }, null) catch |err| {
            log.debug("Failed to initialize logical device: {!}\n", .{err});
            return error.LogicalDeviceFailed;
        };

        // create zig wrapper bindings for the new logical device
        const dev_wrapper = try parent.allocator.create(vk.DeviceWrapper);
        errdefer parent.allocator.destroy(dev_wrapper);

        dev_wrapper.* = vk.DeviceWrapper.load(
            logical_dev,
            parent.w_di.dispatch.vkGetDeviceProcAddr.?,
        );

        if (dev_wrapper.dispatch.vkDestroyDevice == null) {
            log.debug("Failed to load dispatch table\n", .{});
            return error.DispatchLoadingFailed;
        } else {
            log.debug("Dispatch loading successful\n", .{});
        }

        const dev_proxy = vk.DeviceProxy.init(logical_dev, dev_wrapper);

        const cmd_pool = try dev_proxy.createCommandPool(&.{
            .flags = .{ .reset_command_buffer_bit = true },
            .queue_family_index = dev_queue_indices.graphics_family.?,
        }, null);

        return DeviceHandler{
            .ctx = parent,
            .dev_wrapper = dev_wrapper,
            .pr_dev = dev_proxy,
            .h_dev = logical_dev,
            .h_pdev = chosen_dev,
            .h_cmd_pool = cmd_pool,
            .families = dev_queue_indices,
            .swapchain_details = swapchain_details,
            .props = dev_properties,
        };
    }

    pub fn deinit(self: *DeviceHandler) void {
        self.pr_dev.destroyCommandPool(self.h_cmd_pool, null);
        self.pr_dev.destroyDevice(null);

        self.ctx.allocator.destroy(self.dev_wrapper);
        self.swapchain_details.deinit();
    }

    pub fn getMemProperties(self: *const DeviceHandler) vk.PhysicalDeviceMemoryProperties {
        return self.ctx.pr_inst.getPhysicalDeviceMemoryProperties(self.h_pdev);
    }

    pub fn getQueue(
        self: *const DeviceHandler,
        comptime family: QueueType,
    ) ?api.GenericQueue(family) {
        const index = switch (family) {
            .Graphics => self.families.graphics_family orelse return null,
            .Compute => self.families.compute_family orelse return null,
            .Present => self.families.present_family orelse return null,
        };

        const handle = self.pr_dev.getDeviceQueue(index, 0);
        return api.GenericQueue(family).fromHandle(self, handle);
    }

    pub fn draw(
        self: *const DeviceHandler,
        cmd_buf: *const CommandBuffer,
        vert_count: u32,
        inst_count: u32,
        first_vert: u32,
        first_inst: u32,
    ) void {
        self.pr_dev.cmdDraw(
            cmd_buf.h_cmd_buffer,
            vert_count,
            inst_count,
            first_vert,
            first_inst,
        );
    }

    pub fn drawIndexed(
        self: *const DeviceHandler,
        cmd_buf: *const CommandBuffer,
        index_count: u32,
        instance_count: u32,
        first_index: u32,
        vertex_offset: i32,
        first_instance: u32,
    ) void {
        self.pr_dev.cmdDrawIndexed(
            cmd_buf.h_cmd_buffer,
            index_count,
            instance_count,
            first_index,
            vertex_offset,
            first_instance,
        );
    }

    pub fn waitIdle(self: *const DeviceHandler) !void {
        try self.pr_dev.deviceWaitIdle();
    }
};

//TODO: Yeet
pub const SurfaceHandler = struct {
    pub const log = std.log.scoped(.surface);
    h_window: *const glfw.Window = undefined,
    h_surface: vk.SurfaceKHR = .null_handle,
    ctx: *const InstanceHandler = undefined,

    pub fn init(window: *const glfw.Window, ctx: *const InstanceHandler) !SurfaceHandler {
        var surface: vk.SurfaceKHR = undefined;

        if (glfw.glfwCreateWindowSurface(ctx.pr_inst.handle, window.handle, null, &surface) != .success) {
            log.debug("failed to create window surface!", .{});
            return error.SurfaceCreationFailed;
        }

        return SurfaceHandler{
            .h_window = window,
            .h_surface = surface,
            .ctx = ctx,
        };
    }

    pub fn deinit(self: *SurfaceHandler) void {
        self.ctx.pr_inst.destroySurfaceKHR(self.h_surface, null);
    }
};
