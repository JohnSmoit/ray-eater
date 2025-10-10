//! These testing utilities are intended to be used soley for testing blocks
//! and will cause a compilation error if imported outside of a testing binary.

comptime {
    const builtin = @import("builtin");
    if (!builtin.is_test)
        @compileError("DO NOT USE THIS MODULE OUTSIDE TESTING BRUH");
}

const std = @import("std");
const api = @import("../api/api.zig");
const glfw = @import("glfw");

pub const MinimalVulkanContext = struct {
    const Config = struct {
        noscreen: bool = false,
    };

    dev: api.DeviceHandler,
    inst: api.InstanceHandler,

    di: api.DeviceInterface,
    ii: api.InstanceInterface,
    gi: api.GlobalInterface,

    mem_layout: api.DeviceMemoryLayout,
    /// Creates an extremely stripped-down minimal
    /// vulkan context without most of the core rendering utilities.
    /// Do not use for normal rendering.
    pub fn initMinimalVulkan(
        allocator: std.mem.Allocator, 
        config: Config,
    ) !*MinimalVulkanContext {
        const new_ctx = try allocator.create(MinimalVulkanContext);

        try glfw.init();

        const min_inst_ext = [_][*:0]const u8{
            api.extensions.khr_get_physical_device_properties_2.name,
            api.extensions.ext_debug_utils.name,
            api.extensions.khr_surface.name,
        };

        const min_dev_ext = [_][*:0]const u8{
            api.extensions.khr_swapchain.name,
        };


        new_ctx.inst = try api.InstanceHandler.init(.{
            .instance = .{
                .required_extensions = min_inst_ext[0..],
                .validation_layers = &.{
                    "VK_LAYER_KHRONOS_validation",
                },
            },
            .allocator = allocator,
            .enable_debug_log = true,
            .loader = glfw.getInstanceProcAddress,
        });
        errdefer new_ctx.inst.deinit();

        new_ctx.dev = try api.DeviceHandler.init(&new_ctx.inst, .{
            .required_extensions = min_dev_ext[0..],
            .surface = null,
        });

        new_ctx.gi = &new_ctx.inst.w_db;
        new_ctx.ii = &new_ctx.inst.pr_inst;
        new_ctx.di = &new_ctx.dev.pr_dev;
        
        new_ctx.mem_layout = api.DeviceMemoryLayout.init(.{
            .dev = &new_ctx.dev,
            .ii = new_ctx.ii,
        });

        _ = config;

        return new_ctx;
    }
    
    /// Allocator should be the same allocator used to initialize
    /// the structure
    pub fn deinit(
        ctx: *MinimalVulkanContext, 
        allocator: std.mem.Allocator
    ) void {
        ctx.dev.deinit();
        ctx.inst.deinit();

        allocator.destroy(ctx);

        glfw.deinit();
    }
};


