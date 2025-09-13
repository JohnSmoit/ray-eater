//! A heap is a blob of memory which can
//! be partitioned into blocks of arbitrary sizes
//! It gives 0 shits about anything other then
//! allocating and deallocating memory ranges.
//! Think of it more as a view into a section of the device's memory
//! layout rather than the actual memory itself.
//! The actual memory properties are just stored in DeviceMemoryLayout
//! to prevent unnecesary duplication.

const common = @import("common");
const util = common.util;
const vk = @import("vulkan");
const std = @import("std");

const debug = std.debug;

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
    const props = env.mem_layout.getBasicHeapProps(heap_index) orelse
        return 0;
    return util.pct(props.max_size, 75);
}

pub fn init(env: Env, heap_index: u32) Heap {
    // figure out how much memory we can allocate
    return Heap {
        .env              = env,
        .index            = heap_index,
        .available_budget = calcAvailableBudget(env, heap_index),
    };
}

inline fn matchesMask(bit: u32, mask: u32) bool {
    return mask & (@as(u32, 1) << bit) != 0;
}

pub fn alloc(
    heap: *Heap, 
    mem_type: u32, 
    reqs: vk.MemoryRequirements,
) Error!vk.DeviceMemory {
    debug.assert(mem_type < vk.MAX_MEMORY_TYPES);
    debug.assert(matchesMask(mem_type, reqs.memory_type_bits));
    util.assertMsg(reqs.size >= util.megabytes(16), 
        "Due to GPU memory restrictions, small dedicated allocations must use \"allocSmall\"",
    );

    return heap.env.di.allocateMemory(&.{
        .allocation_size   = reqs.size,
        .memory_type_index = mem_type,
    }, null);
}

pub fn allocWithProps(
    heap: *Heap, 
    props: vk.MemoryPropertyFlags, 
    reqs: vk.MemoryRequirements,
) Error!vk.DeviceMemory {
    const mem_type = heap.env.mem_layout.compatibleTypeInHeap(heap.index, props) orelse
    return error.IncompatibleProperties;

    return heap.alloc(mem_type, reqs);
}

pub fn free(heap: *Heap, mem: vk.DeviceMemory) void {
    heap.env.di.freeMemory(mem, null);
}


// Comptime-invoked so that
// optional features can be enabled
// given required extensions are present.
// TODO: Feature sets n stuff
//pub fn requestExtensions(fs: FeatureSet) []const ?[:0]const u8 {
//    return &.{
//        fs.ifEnabled("VK_EXT_memory_budget", .AccurateHeapReadouts),
//    };
//}

const testing = std.testing;

const ray = @import("../../root.zig");
const TestingContext = ray.testing.MinimalVulkanContext;

test "raw heap allocations" {
    const testing_props = vk.MemoryPropertyFlags{
        .host_visible_bit = true,
        .host_coherent_bit = true,
    };
    var minimal_vulkan = try TestingContext.initMinimalVulkan(testing.allocator, .{
        .noscreen  = true,
    });
    defer minimal_vulkan.deinit(testing.allocator);

    const test_heap_index = minimal_vulkan.mem_layout.findSupportingHeap(
        testing_props,
    ) orelse return error.NoMatchingHeap;

    var heap = minimal_vulkan.mem_layout.acquireHeap(test_heap_index);

    // Raw map memory for a write/read cycle
    const mem_handle = try heap.allocWithProps(testing_props, .{
    });

    const mem = try minimal_vulkan.di.mapMemory(mem_handle);
    mem.* = "100 bottles of beer on the wall";

    try minimal_vulkan.di.unmapMemory(mem_handle);
    // If it doesn't segfault or yield validation errors, then it worked.
}
