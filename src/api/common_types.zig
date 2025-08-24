const vk = @import("vulkan");

pub const SyncInfo = struct {
    fence_sig: ?vk.Fence = null,
    fence_wait: ?vk.Fence = null,

    sem_sig: ?vk.Semaphore = null,
    sem_wait: ?vk.Semaphore = null,
};

pub const DescriptorUsageInfo = packed struct {
    /// THis just directly controls which pool the descriptor is 
    /// allocated into. For the moment, all descriptors will be
    /// either transient or application scoped
    pub const LifetimeScope = enum(u3) {
        /// descriptor exists for just a single frame
        /// which places it into the "transient" pool
        Transient, 

        /// Descriptor exists for a longer time, but 
        /// can still be freed and replaced. This pool still follows vulkan
        /// rules, but "freed" descriptors are placed into a free store
        /// which allows them to be rewritten instead of being completely reallocated.
        Scene,

        /// These descriptors are completely static. Never to be freed until the application dies
        Static,
    };

    lifetime_bits: LifetimeScope,
};

pub const DescriptorType = enum(u8) {
    Uniform,
    Sampler,
    StorageBuffer,
    Image,

    pub fn toVkDescriptor(self: DescriptorType) vk.DescriptorType {
        return switch(self) {
            .Uniform => .uniform_buffer,
            .Sampler => .combined_image_sampler,
            .StorageBuffer => .storage_buffer,
            .Image => .storage_image,
        };
    }

    pub fn toIndex(self: DescriptorType) usize {
        return @intFromEnum(self);
    }
};
