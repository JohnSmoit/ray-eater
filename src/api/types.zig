const vk = @import("vulkan");

pub const SyncInfo = struct {
    fence_sig: ?vk.Fence = null,
    fence_wait: ?vk.Fence = null,

    sem_sig: ?vk.Semaphore = null,
    sem_wait: ?vk.Semaphore = null,
};
