const std = @import("std");
const vk = @import("vulkan");
const util = @import("../util.zig");

const Context = @import("../context.zig");


const Swapchain = @import("swapchain.zig");
const DeviceHandler = @import("base.zig").DeviceHandler;
const CommandBuffer = @import("command_buffer.zig");

pub const QueueFamily = enum {
    Graphics,
    Present,
    Compute,
};

pub fn GenericQueue(comptime p_family: QueueFamily) type {
    return struct {
        pub const log = std.log.scoped(.queue);

        const family = p_family;
        pub const Self = @This();

        h_queue: vk.Queue,
        pr_dev: *const vk.DeviceProxy,

        pub fn initDev(dev: *const DeviceHandler) !Self {
            const queue_handle: vk.Queue = dev.getQueueHandle(family) orelse {
                log.debug("Failed to acquire Queue handle", .{});
                return error.MissingQueueHandle;
            };

            return .{
                .h_queue = queue_handle,
                .pr_dev = &dev.pr_dev,
            };
        }

        pub fn init(ctx: *const Context) !Self {
            const dev: *const DeviceHandler = ctx.env(.dev);
            return initDev(dev);
        }

        pub fn deinit(self: *Self) void {
            // TODO: Annihilate queue

            _ = self;
        }

        pub fn submit(
            self: *const Self,
            cmd_buf: *const CommandBuffer,
            sem_wait: ?vk.Semaphore,
            sem_sig: ?vk.Semaphore,
            fence_wait: ?vk.Fence,
        ) !void {
            const wait_stages = [_]vk.PipelineStageFlags{.{ .color_attachment_output_bit = true }};
            const submit_info = vk.SubmitInfo{
                .command_buffer_count = 1,
                .p_command_buffers = util.asManyPtr(
                    vk.CommandBuffer,
                    &cmd_buf.h_cmd_buffer,
                ),
                .wait_semaphore_count = if (sem_wait != null) 1 else 0,
                .p_wait_semaphores = util.asManyPtr(vk.Semaphore, &(sem_wait orelse .null_handle)),
                .p_wait_dst_stage_mask = &wait_stages,

                .signal_semaphore_count = if (sem_sig != null) 1 else 0,
                .p_signal_semaphores = util.asManyPtr(vk.Semaphore, &(sem_sig orelse .null_handle)),
            };
            try self.pr_dev.queueSubmit(
                self.h_queue,
                1,
                util.asManyPtr(
                    vk.SubmitInfo,
                    &submit_info,
                ),
                fence_wait orelse .null_handle,
            );
        }

        pub fn waitIdle(self: *const Self) void {
            self.pr_dev.queueWaitIdle(self.h_queue) catch {};
        }

        pub fn present(
            self: *const Self,
            swapchain: *const Swapchain,
            image_index: u32,
            sem_wait: ?vk.Semaphore,
        ) !void {
            _ = try self.pr_dev.queuePresentKHR(self.h_queue, &.{
                .wait_semaphore_count = if (sem_wait != null) 1 else 0,
                .p_wait_semaphores = util.asManyPtr(vk.Semaphore, &(sem_wait orelse .null_handle)),
                .swapchain_count = 1,
                .p_swapchains = util.asManyPtr(vk.SwapchainKHR, &swapchain.h_swapchain),
                .p_image_indices = util.asManyPtr(u32, &image_index),
                .p_results = null,
            });
        }
    };
}

pub const GraphicsQueue = GenericQueue(.Graphics);
pub const PresentQueue = GenericQueue(.Present);
pub const ComputeQueue = GenericQueue(.Compute);
