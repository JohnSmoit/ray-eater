const std = @import("std");
const api = @import("api.zig");
const vk = @import("vulkan");
const base = @import("base.zig");
const util = @import("common").util;
const queue = @import("queue.zig");
const env = @import("../env.zig");

const Context = @import("../context.zig");
const DeviceHandler = base.DeviceHandler;
const GraphicsQueue = queue.GraphicsQueue;

const Self = @This();

pub const log = std.log.scoped(.command_buffer);
h_cmd_buffer: vk.CommandBuffer,
h_cmd_pool: vk.CommandPool,

dev: *const DeviceHandler,
one_shot: bool = false,


pub fn init(ctx: *const Context, config: CommandBuffer.Config) !Self {
    const dev = ctx.env(.dev);
    return try initDev(dev, config);
}

fn initDev(dev: *const DeviceHandler, config: CommandBuffer.Config) !Self {
    var cmd_buffer: vk.CommandBuffer = undefined;
    dev.pr_dev.allocateCommandBuffers(
        &.{
            .command_pool = dev.getCommandPool(config.src_queue_family),
            .level = .primary,
            .command_buffer_count = 1,
        },
        @constCast(util.asManyPtr(vk.CommandBuffer, &cmd_buffer)),
    ) catch |err| {
        log.err("Error occured allocating command buffer: {!}", .{err});
        return err;
    };

    var api_cmd_buf = Self{
        .h_cmd_buffer = cmd_buffer,
        .h_cmd_pool = dev.getCommandPool(config.src_queue_family),
        .dev = dev,
    };

    if (config.one_shot) {
        api_cmd_buf.one_shot = true;
        try api_cmd_buf.beginConfig(.{ .one_time_submit_bit = true });
    }

    return api_cmd_buf;
}

pub fn oneShot(dev: *const DeviceHandler, config: CommandBuffer.Config) !Self {
    var buf = try initDev(dev, config);
    buf.one_shot = true;

    try buf.beginConfig(.{ .one_time_submit_bit = true });
    return buf;
}

pub fn begin(self: *const Self) !void {
    try self.beginConfig(.{});
}

pub fn beginConfig(self: *const Self, flags: vk.CommandBufferUsageFlags) !void {
    self.dev.pr_dev.beginCommandBuffer(self.h_cmd_buffer, &.{
        .flags = flags,
        .p_inheritance_info = null,
    }) catch |err| {
        log.err("Failed to start recording command buffer: {!}", .{err});
        return err;
    };
}

pub fn end(self: *const Self) !void {
    self.dev.pr_dev.endCommandBuffer(self.h_cmd_buffer) catch |err| {
        log.err("Command recording failed: {!}", .{err});
        return err;
    };
}

pub fn reset(self: *const Self) !void {
    self.dev.pr_dev.resetCommandBuffer(self.h_cmd_buffer, .{}) catch |err| {
        log.err("Error resetting command buffer: {!}", .{err});
        return err;
    };
}

pub fn submit(self: *const Self, comptime fam: queue.QueueFamily, sync: api.SyncInfo) !void {
    const submit_queue = self.dev.getQueue(fam) orelse return error.Unsupported;
    try submit_queue.submit(
        self,
        sync.sem_wait,
        sync.sem_sig,
        sync.fence_wait,
    );
}

pub fn deinit(self: *const Self) void {
    // make sure the command buffer isn't in use before destroying it..
    self.dev.waitIdle() catch {};
    self.dev.pr_dev.freeCommandBuffers(
        self.h_cmd_pool,
        1,
        util.asManyPtr(vk.CommandBuffer, &self.h_cmd_buffer),
    );
}

const res = @import("../resource_management/res.zig");
const common = @import("common");
const Registry = res.Registry;

pub const CommandBuffer = struct {
    pub const Config = struct {
        src_queue_family: queue.QueueFamily = .Graphics,
        one_shot: bool = false,
    };

    pub const entry_config =
        Registry.EntryConfig{
            .State = CommandBuffer,
            .Proxy = CommandBufferProxy,
            .InitErrors = CommandBufferInitErrors,
            .ConfigType = Config,
            .management = .Pooled,
            .initFn = dummyInit,
            .deinitFn = dummyDeinit,
        };

    h_cmd_buffer: vk.CommandBuffer,
    h_cmd_pool: vk.CommandPool,

    dev: *const DeviceHandler,
    one_shot: bool = false,
};

pub fn addEntries(reg: *Registry) !void {
    reg.addEntry(CommandBuffer);
}

const CommandBufferInitErrors = error{
    Something,
};

fn dummyInit(self: *CommandBuffer, e: env.Empty(), config: CommandBuffer.Config) CommandBufferInitErrors!void {
    _ = e;
    _ = self;
    _ = config;
}

fn dummyDeinit(self: *const CommandBuffer) void {
    _ = self;
}

const crapi = @import("../resource_management/res.zig").Registry.ComptimeAPI;


pub const CommandBufferProxy = struct {
    const CommandBufferHandle = crapi.HandleFor(CommandBuffer);

    handle: CommandBufferHandle,

    //pub const bind = Entry.bindFn;
    //// easier than "Factory.destroyHandle(thing)"
    //pub const deinit = Entry.deinitFn;

    //pub const submit = res.APIFunction(submit);
    //pub const reset = res.APIFunction(reset);
    //pub const begin = res.APIFunction(begin);
    //pub const beginConfig = res.APIFunction(beginConfig);
    //pub const end = res.APIFunction(end);
};
