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
const env = @import("../env.zig");

/// This sucks ass, replacing with an incremental context loader for now,
/// and a more configurable app context later.
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
    pub fn deinit(ctx: *MinimalVulkanContext, allocator: std.mem.Allocator) void {
        ctx.dev.deinit();
        ctx.inst.deinit();

        allocator.destroy(ctx);

        glfw.deinit();
    }
};

const Context = @import("../context.zig");
const res = @import("../resource_management/res.zig");
const util = @import("common").util;

pub const TestingContext = struct {
    const Environment = Context.Environment;
    const ContextBitfield = util.EnumToBitfield(Environment.ContextEnum);

    const PfnCtxInit = *const fn (*TestingContext, *Config) anyerror!void;

    pub const Config = struct {
        _selected: ContextBitfield = undefined,
        populators: []const res.Registry.PfnPopulateRegistry = &.{
            api.populateRegistry,
        },
        fields: []const Environment.ContextEnum = &.{
            .inst,
            .dev,
            .desc,
            .registry,
            .res,
            .mem_layout,
        },

        validation_layers: []const [*:0]const u8 = &.{
            "VK_LAYER_KHRONOS_validation",
        },

        window: ?glfw.Window = null,
        desc_pool_sizes: api.DescriptorPool.PoolSizes = .{
            .transient = 1024,
            .scene = 1024,
            .static = 2048,
        },
    };

    const init_comp_dispatch = std.EnumMap(Environment.ContextEnum, PfnCtxInit).init(.{
        .inst = initInst,
        .surf = initSurf,
        .dev = initDev,
        .desc = initDesc,
        .registry = initRegistry,
        .res = initRes,
        .mem_layout = initMemLayout,
    });

    allocator: std.mem.Allocator,

    env: Environment,

    // backing fields
    global_interface: api.GlobalInterface,
    inst_interface: api.InstanceInterface,
    dev_interface: api.DeviceInterface,

    dev: api.DeviceHandler,
    inst: api.InstanceHandler,
    surf: api.SurfaceHandler,
    descriptor_pool: api.DescriptorPool,
    mem_layout: api.DeviceMemoryLayout,
    registry: res.Registry,
    resources: res.ResourceManager,

    window: ?glfw.Window,

    fn initInst(ctx: *TestingContext, cfg: *Config) !void {
        ctx.inst = try api.InstanceHandler.init(.{
            .allocator = ctx.allocator,
            .enable_debug_log = true,
            .loader = glfw.getInstanceProcAddress,
            .instance = .{
                .validation_layers = cfg.validation_layers,
                .required_extensions = &.{
                    api.extensions.ext_debug_utils.name,
                    api.extensions.khr_surface.name,
                    //TODO: create proper platform window surface for non-windows users
                    api.extensions.khr_win_32_surface.name,
                    api.extensions.khr_get_physical_device_properties_2.name,
                },
            }
        });

        ctx.global_interface = &ctx.inst.w_db;
        ctx.inst_interface = &ctx.inst.pr_inst;
    }

    fn initDev(ctx: *TestingContext, cfg: *Config) !void {
        ctx.dev = try api.DeviceHandler.init(&ctx.inst, .{
            .required_extensions = &.{
                api.extensions.khr_swapchain.name,
            },
            .surface = if (cfg._selected.has(.surf))
                &ctx.surf
            else
                null,
        });

        ctx.dev_interface = &ctx.dev.pr_dev;
    }

    fn initSurf(ctx: *TestingContext, cfg: *Config) !void {
        ctx.surf = try api.SurfaceHandler.init(if (ctx.window) |*w|
            w
        else
            null, &ctx.inst);

        _ = cfg;
    }

    fn initDesc(ctx: *TestingContext, cfg: *Config) !void {
        var e: api.DescriptorPool.Env = undefined;
        env.populate(&e, ctx.env);

        try ctx.descriptor_pool.initSelf(e, cfg.desc_pool_sizes);
    }

    fn initRes(ctx: *TestingContext, cfg: *Config) !void {
        // needs the resource manager to actually exist first
        // THe type registry will need to be populated from config,
        // as will the general configuration for resource manager
        _ = ctx;
        _ = cfg;

        @panic("Please implmenet the resource manager first!");
    }

    fn initMemLayout(ctx: *TestingContext, cfg: *Config) !void {
        var e: api.DeviceMemoryLayout.Env = undefined;
        env.populate(&e, ctx.env);

        ctx.mem_layout = api.DeviceMemoryLayout.init(e);
        _ = cfg;
    }

    fn initRegistry(ctx: *TestingContext, cfg: *Config) !void {
        ctx.registry = try res.Registry.init(ctx.allocator);

        // populate registry with predefined sources
        for (cfg.populators) |populator| {
            try populator(&ctx.registry);
        }
    }

    /// Initializes only the specified env fields for a testing context
    pub fn initFor(ctx: *TestingContext, cfg: Config) !void {
        ctx.env = Environment.init(ctx);

        ctx.window = cfg.window;

        var cfg2 = cfg;
        cfg2._selected = ContextBitfield.initPopulated(cfg.fields);

        for (cfg.fields) |fld| {
            const initializer = init_comp_dispatch.getAssertContains(fld);
            try initializer(ctx, &cfg2);
        }
    }

    pub fn deinit(ctx: *TestingContext, allocator: std.mem.Allocator) void {
        _ = ctx;
        _ = allocator;
    }
};
