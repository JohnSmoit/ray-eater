const vk = @import("vulkan");
const std = @import("std");
const util = @import("../util.zig"); //TODO: avorelative id relative if possible
const shader = @import("shader.zig");

// note: Yucky
const glfw = @import("glfw");

// logging stuff
const global_log = std.log;
const validation_log = global_log.scoped(.validation);

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
    window: *glfw.Window,
    allocator: Allocator,
    enable_debug_log: bool,
};

fn debugCallback(message_severity: vk.DebugUtilsMessageSeverityFlagsEXT, message_type: vk.DebugUtilsMessageTypeFlagsEXT, p_callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT, p_user_data: ?*anyopaque) callconv(.c) vk.Bool32 {
    const callback_data = p_callback_data orelse {
        validation_log.err("Something probably bad happened but vulkan won't fucking give me the info", .{});
        return vk.FALSE;
    };

    // TODO: Handle the bitset flags as independent enum values...
    // That way, logging levels will work for vulkan validation as well..
    const msg_level = message_severity.toInt();

    validation_log.debug("{d} -- {s}", .{ msg_level, callback_data.p_message orelse "Fuck" });

    _ = message_type;
    _ = p_user_data;

    return vk.FALSE;
}
// use a bunch of bullshit global state to test VkInstance creation
pub const Context = struct {
    pub const log = global_log.scoped(.context);
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

    fn createInstance(self: *Context, config: *const ContextConfig) !void {

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

        // TODO: Conditionally enable validation layers/logging based on config property
        // if (config.enable_debug_log) {
        // }

        // TODO: make sure our wanted extensions are available
        //TODO: Not sure I setup the validatiopn layer configs correctly (uh oh)
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
            log.debug("Function loading failed (optional contains a null value)", .{});
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
        errdefer ctx.allocator.destroy(ctx.w_di);

        try ctx.createDebugMessenger();
        errdefer ctx.pr_inst.destroyDebugUtilsMessengerEXT(ctx.h_dmsg, null);

        return ctx;
    }

    pub fn deinit(self: *Context) void {
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

// ====================================
// ******* Logical Device API *********
// ====================================

pub const DeviceConfig = struct {
    surface: *const Surface,
    required_extensions: []const [*:0]const u8 = &[0][*:0]const u8{},
};

pub const Device = struct {
    pub const log = global_log.scoped(.device);
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
        surface: *const Surface,
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

    ctx: *const Context,
    families: FamilyIndices,
    swapchain_details: SwapchainSupportDetails,

    h_dev: vk.Device = .null_handle,
    h_pdev: vk.PhysicalDevice = .null_handle,

    pr_dev: vk.DeviceProxy,
    dev_wrapper: *vk.DeviceWrapper = undefined,

    fn getQueueFamilies(
        dev: vk.PhysicalDevice,
        pr_inst: *const vk.InstanceProxy,
        surface: *const Surface,
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
        defer allocator.free(dev_queue_family_props);

        for (dev_queue_family_props, 0..) |props, index| {
            const i: u32 = @intCast(index);
            if (props.queue_flags.contains(.{
                .graphics_bit = true,
            })) {
                found_indices.graphics_family = i;
            }

            if ((pr_inst.getPhysicalDeviceSurfaceSupportKHR(
                dev,
                i,
                surface.h_surface,
            ) catch vk.FALSE) == vk.FALSE) {
                found_indices.present_family = i;
            }
        }

        return found_indices;
    }

    fn pickSuitablePhysicalDevice(
        pr_inst: *const vk.InstanceProxy,
        config: *const DeviceConfig,
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

        var chosen_dev: ?vk.PhysicalDevice = null;
        dev_loop: for (physical_devices) |dev| {
            const dev_properties = pr_inst.getPhysicalDeviceProperties(dev);
            log.debug(
                \\Found Device Named {s}
                \\    ID: {d}
                \\    Type: {d} 
                \\
            , .{ dev_properties.device_name, dev_properties.device_id, dev_properties.device_type });

            const dev_queue_indices = getQueueFamilies(dev, pr_inst, config.surface, allocator);

            // check to see if device supports presentation (it must or it crashes)
            const supported_extensions = pr_inst.enumerateDeviceExtensionPropertiesAlloc(
                dev,
                null,
                allocator,
            ) catch util.emptySlice(vk.ExtensionProperties);

            ext_loop: for (config.required_extensions) |req| {
                var found = false;

                for (supported_extensions) |ext| {
                    if (std.mem.orderZ(u8, @ptrCast(&ext.extension_name), req) == .eq) {
                        found = true;
                        break :ext_loop;
                    }
                }

                if (!found) {
                    continue :dev_loop;
                }
            }

            //NOTE: Ew
            if (dev_queue_indices.graphics_family == null or dev_queue_indices.present_family == null) {
                continue;
            }

            var dev_present_features = getDeviceSupport(
                pr_inst,
                config.surface,
                dev,
                allocator,
            ) catch |err| {
                log.debug("Failed to query device presentation features due to error: {!}\n", .{err});
                continue;
            };
            defer dev_present_features.deinit();

            if (dev_present_features.formats.len != 0 and dev_present_features.present_modes.len != 0) {
                chosen_dev = dev;
                log.debug(
                    \\Chose Device Named {s}
                    \\    ID: {d}
                    \\    Type: {d} 
                    \\
                , .{ dev_properties.device_name, dev_properties.device_id, dev_properties.device_type });

                break;
            }
        }

        return chosen_dev;
    }

    // Later on, I plan to accept a device properties struct
    // which shall serve as the criteria for choosing a graphics unit
    pub fn init(parent: *const Context, config: *const DeviceConfig) !Device {
        // attempt to find a suitable device -- hardcoded for now
        const chosen_dev = pickSuitablePhysicalDevice(
            &parent.pr_inst,
            config,
            parent.allocator,
        ) orelse {
            log.debug("Failed to find suitable device\n", .{});
            return error.NoSuitableDevice;
        };

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

        return Device{
            .ctx = parent,
            .dev_wrapper = dev_wrapper,
            .pr_dev = dev_proxy,
            .h_dev = logical_dev,
            .h_pdev = chosen_dev,
            .families = dev_queue_indices,
            .swapchain_details = swapchain_details,
        };
    }

    pub fn deinit(self: *Device) void {
        self.pr_dev.destroyDevice(null);

        self.ctx.allocator.destroy(self.dev_wrapper);
        self.swapchain_details.deinit();
    }

    fn getQueueHandle(self: *const Device, family: QueueFamily) ?vk.Queue {
        const family_index = switch (family) {
            .Graphics => self.families.graphics_family orelse return null,
            .Present => self.families.present_family orelse return null,
            .Compute => self.families.compute_family orelse return null,
        };

        return self.pr_dev.getDeviceQueue(family_index, 0);
    }
};

// ==================================
// ******* Device Queue API *********
// ==================================
pub const QueueFamily = enum {
    Graphics,
    Present,
    Compute,
};

pub fn GenericQueue(comptime p_family: QueueFamily) type {
    return struct {
        pub const log = global_log.scoped(.queue);

        const family = p_family;
        pub const Self = @This();

        h_queue: vk.Queue,
        dev: *const Device,

        pub fn init(dev: *const Device) !Self {
            // hardcode to graphics queue for now
            const queue_handle = dev.getQueueHandle(family) orelse {
                log.debug("Failed to acquire Queue handle", .{});
                return error.MissingQueueHandle;
            };

            return .{
                .h_queue = queue_handle,
                .dev = dev,
            };
        }

        pub fn deinit(self: *Self) void {
            // TODO: Annihilate queue

            _ = self;
        }
    };
}

pub const GraphicsQueue = GenericQueue(.Graphics);
pub const PresentQueue = GenericQueue(.Present);
pub const ComputeQueue = GenericQueue(.Compute);

pub const Surface = struct {
    pub const log = global_log.scoped(.surface);
    h_window: *glfw.Window = undefined,
    h_surface: vk.SurfaceKHR = .null_handle,
    ctx: *const Context = undefined,

    pub fn init(window: *glfw.Window, ctx: *const Context) !Surface {
        var surface: vk.SurfaceKHR = undefined;

        if (glfw.glfwCreateWindowSurface(ctx.pr_inst.handle, window.handle, null, &surface) != .success) {
            log.debug("failed to create window surface!", .{});
            return error.SurfaceCreationFailed;
        }

        return Surface{
            .h_window = window,
            .h_surface = surface,
            .ctx = ctx,
        };
    }

    pub fn deinit(self: *Surface) void {
        self.ctx.pr_inst.destroySurfaceKHR(self.h_surface, null);
    }
};

// =================================================
// ******* Swapchain Stuff *************************
// =================================================

pub const Swapchain = struct {
    pub const log = global_log.scoped(.swapchain);

    pub const Config = struct {
        requested_format: struct { //TODO: support picking default/picking from multiple
            color_space: vk.ColorSpaceKHR,
            format: vk.Format,
        },
        requested_present_mode: vk.PresentModeKHR,
        requested_extent: vk.Extent2D,
    };

    pub const ImageInfo = struct {
        h_image: vk.Image,
        h_view: vk.ImageView,
    };

    surface_format: vk.SurfaceFormatKHR = undefined,
    present_mode: vk.PresentModeKHR = undefined,
    extent: vk.Extent2D = undefined,
    h_swapchain: vk.SwapchainKHR = undefined,
    dev: *const Device = undefined,
    images: []ImageInfo = util.emptySlice(ImageInfo),

    fn chooseSurfaceFormat(
        available: []const vk.SurfaceFormatKHR,
        config: *const Config,
    ) !vk.SurfaceFormatKHR {
        var chosen_format: ?vk.SurfaceFormatKHR = null;
        for (available) |*fmt| {
            if (fmt.format == config.requested_format.format and
                fmt.color_space == config.requested_format.color_space)
            {
                chosen_format = fmt.*;
                break;
            }
        }

        log.debug("chose present mode: {s}", .{@tagName(chosen_format.?.format)});

        return chosen_format orelse error.NoSuitableFormat;
    }

    fn chooseExtent(
        capabilities: *const vk.SurfaceCapabilitiesKHR,
        config: *const Config,
    ) !vk.Extent2D {
        if (capabilities.current_extent.width != std.math.maxInt(u32)) {
            log.debug("chose natively supported extent", .{});
            return capabilities.current_extent;
        }

        const extent: vk.Extent2D = .{
            .width = std.math.clamp(
                config.requested_extent.width,
                capabilities.min_image_extent.width,
                capabilities.max_image_extent.width,
            ),
            .height = std.math.clamp(
                config.requested_extent.height,
                capabilities.min_image_extent.height,
                capabilities.max_image_extent.height,
            ),
        };

        log.debug("chose extent: [width: {d}, height: {d}]", .{ extent.width, extent.height });
        return extent;
    }

    fn choosePresentMode(
        available: []const vk.PresentModeKHR,
        config: *const Config,
    ) !vk.PresentModeKHR {
        var chosen_mode: ?vk.PresentModeKHR = null;
        for (available) |mode| {
            if (mode == config.requested_present_mode) {
                chosen_mode = mode;
                break;
            }
        }

        log.debug("chose present mode: {s}", .{
            @tagName(chosen_mode.?),
        });
        return chosen_mode orelse error.NoSuitableFormat;
    }

    fn createImageViews(self: *Swapchain) !void {
        const image_handles = try self.dev.pr_dev.getSwapchainImagesAllocKHR(self.h_swapchain, self.dev.ctx.allocator);
        defer self.dev.ctx.allocator.free(image_handles);

        var images = try self.dev.ctx.allocator.alloc(ImageInfo, image_handles.len);

        for (image_handles, 0..) |img, index| {

            // create and assign the corresponding image view
            // this formatting ie ZLS's fault, plz disable auto format on write since it seems to suck ass
            const image_view = try self.dev.pr_dev.createImageView(&.{ .image = img, .view_type = .@"2d", .format = self.surface_format.format, .components = .{
                .r = .identity,
                .g = .identity,
                .b = .identity,
                .a = .identity,
            }, .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            } }, null);

            images[index].h_image = img;
            images[index].h_view = image_view;
        }

        self.images = images;
    }

    pub fn init(
        device: *const Device,
        surface: *const Surface,
        config: *const Config,
    ) !Swapchain {
        // TODO: Swapchain support details should probably lie within the Surface type
        // instead of the device since these details mostly concern properties of the chosen
        // draw surface.
        const details: *const Device.SwapchainSupportDetails = &device.swapchain_details;

        // request an appropriate number of swapchain images
        var image_count: u32 = details.capabilities.min_image_count + 1;
        if (details.capabilities.max_image_count > 0) {
            image_count = @min(image_count, details.capabilities.max_image_count);
        }

        const surface_format = try chooseSurfaceFormat(
            device.swapchain_details.formats,
            config,
        );

        const present_mode = try choosePresentMode(
            device.swapchain_details.present_modes,
            config,
        );

        const extent = try chooseExtent(
            &device.swapchain_details.capabilities,
            config,
        );

        // make sure the swapchain knows about the relationship between our queue families
        // (i.e which families map to which queues or if both map to one and such)
        var queue_indices = [_]u32{
            device.families.graphics_family.?,
            device.families.present_family.?,
        };

        var image_sharing_mode: vk.SharingMode = .exclusive;
        var queue_family_index_count: u32 = 0;
        var p_queue_family_indices: ?[*]u32 = null;
        if (queue_indices[0] != queue_indices[1]) {
            image_sharing_mode = .concurrent;
            queue_family_index_count = queue_indices.len;
            p_queue_family_indices = &queue_indices;
        }

        // specify the gajillion config values to create the swapchain
        var chain = Swapchain{
            .surface_format = surface_format,
            .present_mode = present_mode,
            .extent = extent,
            .dev = device,

            // the giant ass struct for swapchain creation starts here
            .h_swapchain = try device.pr_dev.createSwapchainKHR(&.{
                .surface = surface.h_surface,

                // drop in the queried values
                .min_image_count = image_count,
                .image_format = surface_format.format,
                .image_color_space = surface_format.color_space,
                .present_mode = present_mode,
                .image_extent = extent,

                //hardcoded (for now) values
                .image_array_layers = 1,
                .image_usage = .{ .color_attachment_bit = true },

                // image sharing properties (controls how queues can access and work in tandem)
                // with a given swapchain image
                .image_sharing_mode = image_sharing_mode,
                .queue_family_index_count = queue_family_index_count,
                .p_queue_family_indices = p_queue_family_indices,

                // whether or not to transform the rendered image before presenting
                .pre_transform = details.capabilities.current_transform,

                // whether to take the alpha channel into account to do cross-window blending (weird)
                .composite_alpha = .{ .opaque_bit_khr = true },

                // ignore obscured pixels (i.e covered by another window)
                .clipped = vk.TRUE,

                // old swapchain (used for swapchain recreation which will come later)
                .old_swapchain = .null_handle,
            }, null),
        };
        // TODO: Figure out a better deallocation strategy then this crap

        // get handles to the created images and create their associated views
        // (which has to be done AFTER the swapchain is created hence the var instead of const)
        try chain.createImageViews();

        return chain;
    }

    pub fn deinit(self: *const Swapchain) void {
        for (self.images) |*info| {
            self.dev.pr_dev.destroyImageView(info.h_view, null);
        }

        self.dev.ctx.allocator.free(self.images);

        // NOTE: The image handles are owned by the swapchain and therefore shouold not be destroyed by me.
        self.dev.pr_dev.destroySwapchainKHR(self.h_swapchain, null);
    }
};

// ============================
// ******* SHADERS ************
// ============================
