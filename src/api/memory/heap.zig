//! A heap is a blob of memory which can
//! be partitioned into blocks of arbitrary sizes
//! It gives 0 shits about anything other then
//! allocating and deallocating memory ranges.
//! Think of it more as a view into a section of the device's memory
//! layout rather than the actual memory itself.
//! The actual memory properties are just stored in DeviceMemoryLayout
//! to prevent unnecesary duplication.

const common = @import("common");
const vk = @import("vulkan");
const std = @import("std");

const debut = std.debug;

const Heap = @This();

const Context = @import("../../context.zig");

pub const Env = Context.EnvSubset(.{.mem_layout, .di});

pub const Error = error {
    DeviceOutOfMemory,
    IncompatibleProperties,
};

env: Env,
index: u32,
available_budget: usize,

/// Calculates based on the budget returned by
/// the vulkan extension, or in absence, using a heuristic
/// based on the total memory of said heap.
fn calcAvailableBudget(env: Env, heap_index: u32) usize {
    const props = env.mem_layout.getBasicHeapProps(heap_index);
    
    // calculates a percentage of an integer value
    return common.pct(props.heapSizeBytes(), 75);
}

pub fn init(env: Env, heap_index: u32) Heap {
    // figure out how much memory we can allocate
    return Heap {
        .env = env,
        .index = heap_index,
        .available_budget = calcAvailableBudget(env, heap_index),
    };
}

fn matchesMask(bit: u32, mask: u32) bool {
    return mask & (@as(u32, 1) << bit) != 0;
}

pub fn alloc(
    heap: *Heap, 
    mem_type: u32, 
    reqs: vk.MemoryRequirements,
) Error!vk.DeviceMemory {
    debug.assert(mem_type < vk.MAX_MEMORY_TYPES);
    debug.assert(matchesMask(mem_type, reqs.memory_type_bits));

    return heap.env.di.allocateMemory(&.{
        .allocation_size = mem_reqs.size,
        .memory_type_index = mem_type,
    }, null);
}

pub fn allocWithProps(
    heap: *Heap, 
    props: vk.MemoryProperties, 
    reqs: vk.MemoryRequirements,
) Error!vk.DeviceMemory {
    if (!heap.env.mem_layout.heapSupports(heap.index, props))
        return error.IncompatibleProperties;

    const mem_type = heap.env.mem_layout.compatibleTypeInHeap(heap.index, props) orelse
    return error.IncompatibleProperties;

    return heap.alloc(mem_type, reqs);
}

pub fn free(heap: *Heap, mem: vk.DeviceMemory) void {
    heap.env.di.freeMemory(mem, null);
}
