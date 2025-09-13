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
    IncompatibleProperties,
    OutOfHostMemory,
    OutOfDeviceMemory,
    Unknown,
    InvalidExternalHandle,
    InvalidOpaqueCaptureAddressKHR,
};

/// Since memory type bits are a pain to set manually,
/// I'll try to keep that automated as much as I can,
/// hence the need for this equivalent struct with defualt values
pub const MemoryRequirements = struct {
    size: vk.DeviceSize,
    alignment: vk.DeviceSize,
    memory_type_bits: ?u32 = null,
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
    return mask & (@as(u32, 1) << @intCast(bit)) != 0;
}

pub fn alloc(
    heap: *Heap, 
    mem_type: u32, 
    reqs: MemoryRequirements,
) Error!vk.DeviceMemory {
    var resolved_reqs = reqs;
    if (resolved_reqs.memory_type_bits == null) {
        resolved_reqs.memory_type_bits = @as(u32, 1) << @as(u5, @intCast(mem_type));
    }

    debug.assert(mem_type < vk.MAX_MEMORY_TYPES);
    debug.assert(matchesMask(mem_type, resolved_reqs.memory_type_bits.?));

    util.assertMsg(resolved_reqs.size >= util.megabytes(@as(vk.DeviceSize, 16)), 
        "Due to GPU memory restrictions, small dedicated allocations must use \"allocSmall\"",
    );

    return heap.env.di.allocateMemory(&.{
        .allocation_size   = resolved_reqs.size,
        .memory_type_index = mem_type,
    }, null);
}

pub fn allocWithProps(
    heap: *Heap, 
    props: vk.MemoryPropertyFlags, 
    reqs: MemoryRequirements,
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
        .size = 128,
        .alignment = 1,
    });

    const mem = @as(
        [*]u8, 
        @ptrCast(@alignCast(
            try minimal_vulkan.di.mapMemory(mem_handle, 0, 128, .{})
        )),
    )[0..128];

    std.mem.copyForwards(u8, mem, "100 bottles of beer on the wall");

    minimal_vulkan.di.unmapMemory(mem_handle);
}
