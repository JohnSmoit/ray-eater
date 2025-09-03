const std = @import("std");
const vk = @import("vulkan");
const api = @import("../api.zig");
const heap = @import("heap.zig");

const Context = @import("../../context.zig");

const Layout = @This();
const HeapMap = heap.HeapMap;
const Heap = HeapMap.Handle;

const DeviceLayoutError = error{
    OutOfMemory,
};

raw_mem_props: vk.PhysicalDeviceMemoryProperties,
heaps: HeapMap,

pub fn init(
    ctx: *const Context,
    allocator: std.mem.Allocator,
) DeviceLayoutError!Layout {
    const dev: *const api.DeviceHandler = ctx.env(.dev);
    const ii: api.InstanceInterface = ctx.env(.ii);

    const mem_props = ii.getPhysicalDeviceMemoryProperties(dev.h_pdev);

    const valid_heaps = mem_props.memory_heaps[0..mem_props.memory_heap_count];
    const valid_types = mem_props.memory_types[0..mem_props.memory_type_count];

    return Layout{
        .raw_mem_props = mem_props,
        .heaps = try HeapMap.init(valid_heaps, valid_types, allocator),
    };
}

pub fn heapSupportsType(
    self: *const Layout,
    heap: Heap,
    type_index: usize,
) bool {
    return null;
}

pub fn typeSupportsProperty(self: *const Layout, type_index: usize, properties: vk.MemoryPropertyFlags) bool {}
