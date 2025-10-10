const vk = @import("vulkan");
/// Represents an individual memory allocation..
/// Depending on the allocated memory's properties,
/// Accessing the memory might require creating a staging buffer
/// or flushing and invalidating cached host-mapped memory
///
/// Probably should handleify this, to make allocations more resistant
/// to changes in location and such


pub const DeviceMemoryRange = struct {
    offset: usize,
    size: usize,
};

pub const AllocationData = struct {
    src_heap: vk.DeviceMemory,
    range: DeviceMemoryRange,
};

/// Handle for allocation data
pub const Allocation = common.Handle(AllocationData, .{
    .partition_bit = 12,
});

/// Reified (complete) handle for allocation data
pub const ReifiedAllocation = Allocation.Reified;
