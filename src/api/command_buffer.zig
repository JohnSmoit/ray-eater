const std = @import("std");
const vk = @import("vulkan");
const base = @import("base.zig");
const util = @import("../util.zig");
const queue = @import("queue.zig");

const Context = @import("../context.zig");
const DeviceHandler = base.DeviceHandler;
const GraphicsQueue = queue.GraphicsQueue;

const Self = @This();

pub const log = std.log.scoped(.command_buffer);
h_cmd_buffer: vk.CommandBuffer,
h_cmd_pool: vk.CommandPool,

dev: *const DeviceHandler,
one_shot: bool = false,

pub fn init(ctx: *const Context) !Self {
    const dev = ctx.env(.dev);
    return init_dev(dev);
}

fn init_dev(dev: *const DeviceHandler) !Self {
    var cmd_buffer: vk.CommandBuffer = undefined;
    dev.pr_dev.allocateCommandBuffers(
        &.{
            .command_pool = dev.h_cmd_pool,
            .level = .primary,
            .command_buffer_count = 1,
        },
        @constCast(util.asManyPtr(vk.CommandBuffer, &cmd_buffer)),
    ) catch |err| {
        log.err("Error occured allocating command buffer: {!}", .{err});
        return err;
    };

    return .{
        .h_cmd_buffer = cmd_buffer,
        .h_cmd_pool = dev.h_cmd_pool,
        .dev = dev,
    };

}

pub fn oneShot(dev: *const DeviceHandler) !Self {
    var buf = try init_dev(dev);
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

    // NOTE: For now, I'm going to just hardcode a submit to the graphics queue
    // if a one shot command buffer is used
    // Also, synchronization is not gonna be handled yet...
    // the best way to handle synchronization is to only do 1 thing at a time 😊
    // (by waiting idle)
    
    // We need queue handles from the context straight up, no way around it ugh
    // this shit is too bad to handle otherwise
    if (self.one_shot) {
        const submit_queue = try GraphicsQueue.init(self.ctx);
        try submit_queue.submit(self, null, null, null);
        submit_queue.waitIdle();
    }
}

pub fn reset(self: *const Self) !void {
    self.dev.pr_dev.resetCommandBuffer(self.h_cmd_buffer, .{}) catch |err| {
        log.err("Error resetting command buffer: {!}", .{err});
        return err;
    };
}

pub fn deinit(self: *const Self) void {
    self.dev.pr_dev.freeCommandBuffers(
        self.h_cmd_pool,
        1,
        util.asManyPtr(vk.CommandBuffer, &self.h_cmd_buffer),
    );
}
