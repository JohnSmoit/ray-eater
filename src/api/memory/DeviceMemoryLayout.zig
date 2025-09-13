const std = @import("std");
const vk = @import("vulkan");
const api = @import("../api.zig");

const debug = std.debug;

const Heap = @import("Heap.zig");

const Context = @import("../../context.zig");

const Layout = @This();

//pub const Env = Context.EnvSubset(.{.dev, .ii});
pub const Env = struct {
    dev: *const api.DeviceHandler,
    ii: api.InstanceInterface,
};

const DeviceLayoutError = error{
    OutOfMemory,
    OutOfBounds,
};

/// Basic properties of a memory heap...
/// TODO: Extend std's MultiArray to support sparse indexing
const HeapProperties = struct {
    max_size: usize,
    supported_type_props: vk.MemoryPropertyFlags,
};

raw_mem_props: vk.PhysicalDeviceMemoryProperties,
// heaps: HeapMap,

// index tables for memory properties
prop_type_index: [vk.MAX_MEMORY_TYPES]vk.MemoryPropertyFlags,
heap_prop_index: [vk.MAX_MEMORY_HEAPS]HeapProperties,
type_heap_index: [vk.MAX_MEMORY_TYPES]u32,

mem_type_count: usize,
mem_heap_count: usize,

env: Env,

pub fn init(
    env: Env,
) Layout {
    const dev: *const api.DeviceHandler = env.dev;
    const ii: api.InstanceInterface = env.ii;

    const mem_props = ii.getPhysicalDeviceMemoryProperties(dev.h_pdev);

    var new_layout = Layout{
        .raw_mem_props = mem_props,

        .prop_type_index = undefined,
        .heap_prop_index = undefined,
        .type_heap_index = undefined,
        
        .mem_type_count = mem_props.memory_type_count,
        .mem_heap_count = mem_props.memory_heap_count,

        .env = env,
    };

    for (0.., 
        &new_layout.prop_type_index, 
        &new_layout.type_heap_index,
    ) |i, *prop, *h| {
        prop.* = mem_props.memory_types[i].property_flags;
        h.* = mem_props.memory_types[i].heap_index;
    }

    for (0.., &new_layout.heap_prop_index) |i, *prop| {
        prop.* = HeapProperties{
            .max_size = mem_props.memory_heaps[i].size,
            .supported_type_props = undefined,
        };
    }

    return new_layout;
}

pub fn getBasicHeapProps(layout: *const Layout, heap: u32) ?HeapProperties {
    if (heap > vk.MAX_MEMORY_HEAPS) return null;
    return layout.heap_prop_index[heap];
}


pub fn compatibleTypeInHeap(
    layout: *const Layout, 
    heap: u32, 
    props: vk.MemoryPropertyFlags
) ?u32 {
    for (0..layout.mem_type_count) |t| {
        if (layout.type_heap_index[t] != heap) continue;
        const type_props = layout.prop_type_index[t];
        
        if (type_props.contains(props)) return @intCast(t);
    }

    return null;
}

pub fn findSupportingHeap(
    layout: *const Layout, 
    props: vk.MemoryPropertyFlags
) ?u32 {
    for (0..layout.mem_heap_count) |h| {
        const heap_props = layout.heap_prop_index[h].supported_type_props;
        if (heap_props.contains(props)) return @intCast(h);
    }

    return null;
}

/// You now own the heap as it is an active view of the
/// device's memory as opposed to a passive overview such as this
pub fn acquireHeap(layout: *Layout, index: u32) Heap {
    debug.assert(index < layout.mem_heap_count);

    return Heap.init(.{
        .mem_layout = layout,
        .di = &layout.env.dev.pr_dev, //TODO: Rename pr_dev as di
    }, index);
}


//pub fn heapSupportsType(
//    self: *const Layout,
//    heap: Heap,
//    type_index: usize,
//) bool {
//    return null;
//}

//pub fn typeSupportsProperty(self: *const Layout, type_index: usize, properties: vk.MemoryPropertyFlags) bool {}
