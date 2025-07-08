const std = @import("std");
const api = @import("api.zig");

const e = @import("env.zig");

const Allocator = std.mem.Allocator;

const Device = api.Device;
const Instance = api.Instance;

const GlobalInterface = api.GlobalInterface;
const InstanceInterface = api.InstanceInterface;
const DeviceInterface = api.DeviceInterface;
const VulkanAPI = api.VulkanAPI;

const Ref = e.Ref;
const ContextEnv = struct {
    inst: Ref(Instance, .{}),
    dev: Ref(Device, .{}),

    gi: Ref(GlobalInterface, .{.field = "global_interface"}),
    ii: Ref(InstanceInterface, .{.field = "inst_interface"}),
    di: Ref(DeviceInterface, .{.field = "dev_interface"}),
};
const Environment = e.For(ContextEnv);

const Self = @This();

ctx_env: Environment,

inst: Instance,
dev: Device,

// NOTE: For loading vulkan APIs it might be a good idea to heap-allocate those due to the fact
// they are thicc as hell (DeviceInterface is like 6kb of straight function pointers)
// and as such passing them around on the stack might suck

// these can be assigned as pointers into the vk_api field
// validity won't be a problem if the API is heap allocated, which I think is a fair compromise
// in this case
// these'll become valid once initialization is fully complete for instances
// and devices, until that happens they just point to uninitialized heap memory
global_interface: *const GlobalInterface,
inst_interface: *const InstanceInterface,
dev_interface: *const DeviceInterface,

vk_api: *const VulkanAPI, // heap allocated cuz big

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
pub fn env(self: *const Self, comptime field: anytype) ResolveEnvType(field) {
    const Res = ResolveEnvType(field);

    return switch (Res) {
        *const Environment => &self.ctx_env,
        else => self.ctx_env.get(@as(Environment.ContextEnum, field)), 
    };
}


/// TODO: maybe have an unmanaged variant for more fine-grained user control
/// over memory allocations
pub fn init(allocator: Allocator) Self {

    const api_ref = try allocator.create(VulkanAPI);

    // Initialize Instance and device from parameters

    const inst = try Instance.init(.{
        .instance
    });

    return .{
        .ctx_env = undefined,
        .vk_api = api_ref,

        .global_interface = &api_ref.global_interface,
        .inst_interface = &api_ref.inst_interface,
        .dev_interface = &api_ref.dev_interface,
        
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    self.allocator.?.destroy(self.vk_api);
}
