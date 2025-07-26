//!Helpful wrappers for GPU syncrhonization

const std = @import("std");
const api = @import("api.zig");
const vk = @import("vulkan");
const Context = @import("../context.zig");

pub const Semaphore = struct {
    pr_dev: *const api.DeviceInterface,
    h_sem: vk.Semaphore,
    pub fn init(ctx: *const Context) !Semaphore {
        const pr_dev: *const api.DeviceInterface = ctx.env(.di);
        return .{
            .h_sem = try pr_dev.createSemaphore(&.{}, null),
            .pr_dev = pr_dev,
        };
    }

    pub fn deinit(self: *const Semaphore) void {
        self.pr_dev.destroySemaphore(self.h_sem, null);
    }
};

pub const Fence = struct {
    pr_dev: *const api.DeviceInterface,
    h_fence: vk.Fence,
    pub fn init(ctx: *const Context, start_signaled: bool) !Fence {
        const pr_dev: *const api.DeviceInterface = ctx.env(.di);
        return .{
            .h_fence = try pr_dev.createFence(&.{
                .flags = .{
                    .signaled_bit = start_signaled,
                },
            }, null),
            .pr_dev = pr_dev,
        };
    }

    pub fn wait(self: *const Fence) !void {
        _ = try self.pr_dev.waitForFences(1, &.{
            self.h_fence,
        }, vk.TRUE, std.math.maxInt(u64));
    }

    pub fn reset(self: *const Fence) !void {
        try self.pr_dev.resetFences(1, &.{
            self.h_fence
        });
    }

    pub fn deinit(self: *const Fence) void {
        self.pr_dev.destroyFence(self.h_fence, null);
    }
};
