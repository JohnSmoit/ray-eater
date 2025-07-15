const std = @import("std");
const api = @import("api/api.zig");

const glfw = @import("glfw");

const e = @import("env.zig");

const Allocator = std.mem.Allocator;
const ExtensionNameList = std.ArrayList([*:0]const u8);

const Device = api.Device;
const Instance = api.Instance;
const Surface = api.Surface;

const GlobalInterface = api.GlobalInterface;
const InstanceInterface = api.InstanceInterface;
const DeviceInterface = api.DeviceInterface;
const VulkanAPI = api.VulkanAPI;

const Ref = e.Ref;
const EnvBacking = struct {
    inst: Ref(Instance, .{}),
    dev: Ref(Device, .{}),
    surf: Ref(Surface, .{}),

    gi: Ref(GlobalInterface, .{ .field = "global_interface" }),
    ii: Ref(InstanceInterface, .{ .field = "inst_interface" }),
    di: Ref(DeviceInterface, .{ .field = "dev_interface" }),
};
const Environment = e.For(EnvBacking);

const Self = @This();

ctx_env: Environment,

inst: Instance,
dev: Device,
surf: Surface,

global_interface: *const GlobalInterface,
inst_interface: *const InstanceInterface,
dev_interface: *const DeviceInterface,

// NOTE: Planning on centralizing the entire vulkan API into a single struct for better
// management, but not needed for now
// vk_api: VulkanAPI, // heap allocated cuz big

allocator: Allocator,

fn ResolveEnvType(comptime field: anytype) type {
    return switch (@TypeOf(field)) {
        void => *const Environment,
        else => Environment.ResolveInner(@as(Environment.ContextEnum, field)),
    };
}

/// # Valid env specifiers:
/// ### Important Handles
/// Do note that a lot of these handles might end up being abstracted away when cross platforming
/// becomes more of a concern
/// * .inst -> VkInstance (Retrieves application's VkInstance handle, generally not useful for application logic)
/// * .dev -> VkDevice (Retrieves application's VkDevice handle, generally not useful for application logic)
///
/// ### Interfaces
/// * .gi -> global interface (does not require an instanced handle of any kind, generally setup such as extension querying
///        and more broadly, things used to set up an instance)
/// * .ii -> VkInstance interface (autopasses context's VkInstance and includes all instance-scoped vulkan API calls)
/// * .di -> VkDevice interface (autopasses context's VkDevice and includes all device-scoped vulkan API calls)
///
/// ## Extras
/// * void -> entire environment (useful for scoping in API types)
/// 
/// ## Usage Tips:
/// * I STRONGLY recommend using manual type annotation if you want any hints from ZLS whatsoever
///   because zls doesn't really handle comptime stuff very well yet.
pub fn env(self: *const Self, comptime field: anytype) ResolveEnvType(field) {
    const Res = ResolveEnvType(field);

    return switch (Res) {
        *const Environment => &self.ctx_env,
        else => self.ctx_env.get(@as(Environment.ContextEnum, field)),
    };
}

pub const Config = struct {
    inst_extensions: []const [*:0]const u8 = &.{},
    dev_extensions: []const [*:0]const u8 = &.{},
    window: *const glfw.Window,
    loader: glfw.GetProcAddrHandler,
};

/// TODO: maybe have an unmanaged variant for more fine-grained user control
/// over memory allocations
pub fn init(allocator: Allocator, config: Config) !*Self {
    const new = try allocator.create(Self);
    errdefer allocator.destroy(new);

    const base_inst_ext = [_][*:0]const u8{
        api.extensions.khr_get_physical_device_properties_2.name,
        api.extensions.ext_debug_utils.name,
    };

    const base_dev_ext = [_][*:0]const u8{
        api.extensions.khr_swapchain.name,
    };

    var all_inst_ext = try ExtensionNameList.initCapacity(
        allocator,
        base_inst_ext.len + config.inst_extensions.len,
    );
    defer all_inst_ext.deinit();

    var all_dev_ext = try ExtensionNameList.initCapacity(
        allocator,
        base_inst_ext.len + config.dev_extensions.len,
    );
    defer all_dev_ext.deinit();

    all_inst_ext.appendSliceAssumeCapacity(base_inst_ext[0..]);
    all_inst_ext.appendSliceAssumeCapacity(config.inst_extensions);

    all_dev_ext.appendSliceAssumeCapacity(base_dev_ext[0..]);
    all_dev_ext.appendSliceAssumeCapacity(config.dev_extensions);

    // Initialize Instance and device from parameters
    // Later on, I'll have some better ways to handle ownership and lifetimes
    // then just raw heap allocations lol

    // Would be great if errdefers worked in initializers... because I like keeping initialization
    // in initializers when I can

    new.inst = try Instance.init(&.{
        .instance = .{
            .required_extensions = all_inst_ext.items,
            .validation_layers = &.{
                "VK_LAYER_KHRONOS_validation",
            },
        },
        .allocator = allocator,
        .device = undefined,
        .enable_debug_log = true,

        .loader = config.loader,
    });
    errdefer new.inst.deinit();

    new.surf = try Surface.init(config.window, &new.inst);
    errdefer new.surf.deinit();

    new.dev = try Device.init(&new.inst, &.{
        .required_extensions = all_dev_ext.items,
        .surface = &new.surf,
    });
    errdefer new.dev.deinit();
    new.allocator = allocator;

    // link references together
    // the interface references exist for easier access for the env struct
    new.global_interface = &new.inst.w_db;
    new.inst_interface = &new.inst.pr_inst;
    new.dev_interface = &new.dev.pr_dev;

    new.ctx_env = Environment.init(new);

    return new;
}

pub fn deinit(self: *Self) void {
    self.dev.deinit();
    self.surf.deinit();
    self.inst.deinit();

    const alloc = self.allocator;
    alloc.destroy(self);
}
