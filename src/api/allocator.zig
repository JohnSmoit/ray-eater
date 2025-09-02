//! Vulkan-specific allocator for giving user control over host and device-side allocations.
//! Of course, the standard zig allocation interface is great but it's usage doesn't
//! fit well into device-side memory allocations, so we have this.
//!
//! I will do my best to keep the implementation of this allocator be as in-line as possible
//! to the standard memory allocation interface (if I can I will support creating
//! std.mem.Allocators).

const std = @import("std");
const vk = @import("vulkan");
const common = @import("common");
const api = @import("api.zig");

const Context = @import("../context.zig");

/// Represents an individual memory allocation..
/// Depending on the allocated memory's properties,
/// Accessing the memory might require creating a staging buffer
/// or flushing and invalidating cached host-mapped memory
///
/// Probably should handleify this, to make allocations more resistant
/// to changes in location and such
pub const Allocation = struct {
    src_heap: vk.DeviceMemory,
    offset: u32,
    size: u32,
};

const AllocationScope = enum(u2) {
    /// General Purpose, Picks a free-list styled, static heap
    /// (in fact, It'll likely just choose the scene heap outright)
    /// This is the "idontwanttothinkaboutit" option
    General,
    /// Short lived, Maximum of a single frame. This creates the allocation
    /// in a high-performance linear allocator (probably an arena with some bells and whistles)
    /// and invalidates it (clears the buffer) every frame. Use for fire-and-forget operations
    Transient,
    /// Medium Lived, Persists across frames but may be freed/reused if new resources need to be loaded
    /// during runtime. May use a free list or a ring-buffer with an LRU mechanism to clear potentially unused
    /// resources.
    Scene,
    /// Never freed. Exists across all scenes, Note that freeing may be a no-op in some cases
    /// So be careful to only reserve what is necessary for static memory
    Static,
};

const AllocationPropertyFlags = packed struct {
    /// Whether or not memory should be directly mappable on the host
    /// Otherwise, transfers and staging buffers are necessary
    host_mappable: bool = false,

    /// Whether or not memory should be addressable in a sequential manner,
    /// (i.e copied forwards, or maybe backwards).
    seq_access: bool = false,

    /// Whether or not memory should be addressable in a random manner,
    /// (indexing, partial copies, etc). This also implies sequantial access is allowed
    /// so no need to set both .seq_access and this.
    /// Random access will likely prefer cached memory whereas sequential access will prefer coherent.
    rand_access: bool = false,

    /// How long will this allocation live?
    /// This will control which heap and which allocation algorithm
    /// will be used for this allocation
    lifetime_hint: AllocationScope = .General,
};
const StructureHints = packed struct {
    /// Size in bytes of the structure
    /// use for untyped but otherwise fixed-sized resources. Especially if you have multiple of the same
    /// so that the same pool can be used and potentially CPU/GPU time saved with initialization
    ///
    /// This should be an either/or with type_id, as specifying values for both prefers type_id
    size: ?usize = null,

    /// Specific type ID of the structure. Use if you have fixed-sized resource of a known type
    /// This in particlar will prefer a slab allocator over a generic pool.
    /// For best type safe results, Most functions that allocate will accept a comptime type
    /// to interpret the resulting memory in the case of direct host interaction.
    type_id: ?common.TypeId = null,
};

pub const AllocationConfig = packed struct {
    pub const GeneralFlags = packed struct {
        ///General stuff
        /// Whether or not the best fit should be selected in case a perfect
        /// allocator match isn't found
        best_fit: bool = true,

        /// Force the allocator to perform a dedicated
        /// VkAllocateMemory specifically for this allocation (renders most configuration moot)
        force_dedicated: bool = false,
    };

    pub const Resolved = packed struct {
        mem_props: vk.MemoryPropertyFlags,
        mem_reqs: vk.MemoryRequirements,
        general_flags: GeneralFlags,
    };
    /// Directly force an allocation to be for memory with
    /// the specified properties
    /// This will be prioritized over any other settings
    /// So use carefully.
    mem_props_override: ?vk.MemoryPropertyFlags = null,

    /// Requested memory properties, includes various hints for needed
    /// memory operations along with lifetimes.
    /// This is used in picking a heap and memory type in the heap (rather then just mapping
    /// directly to type indices)
    req_mem_props: AllocationPropertyFlags,

    /// The physical requirements for a given resource, such as size,
    /// alignments, and compatible memory types, you can manually specify these,
    /// or use the more convenient "resource_owner" field to infer them from the given resource
    resource_requirements: ?vk.MemoryRequirements = null,

    /// Directly pass in the resource owning the allocation to infer base memory requirements..
    /// Must be a valid handle
    resource_owner: ?union(enum) {
        Buffer: vk.Buffer,
        Image: vk.Image,
    } = null,

    /// Structure hints
    /// This controls whether or not to use a structured memory pool
    /// based on given parameters
    structure_hints: StructureHints = .{},

    general: GeneralFlags = .{},

    /// Flattens all nullable values and optional configuration parameters
    /// into a common resolved layout
    /// This shouldn't fail with an error, but just assert at you if you do invalid config
    pub fn flatten(self: *const AllocationConfig) Resolved {}
};

/// Just a thin wrapper over a VkDeviceMemory with some extra crap
/// Think of this as an individual device memory, the only real difference is that
/// it supports suballocations on a less granular page size.
const GPUBlock = struct {
    parent_heap: *const Heap,
    mem: vk.DeviceMemory,

    /// offset into physical GPU memory pool,
    /// Probably can save some bits since pages will be relatively large
    break_limit: u16,
    page_count: u16,

    /// Performs exactly one GPU allocation of the specified # of pages
    /// (determined by the parent heap)
    ///
    /// This function should not be allowed to error, since budgets and memory
    /// limits should be figured out ahead of time. Essentially, a new block
    /// should only ever be created if there is actually space for one.
    pub fn init(heap: *Heap, page_count: u16) GPUBlock {
    }
};

/// Individual memory heap,
/// This maps cleanly onto vulkan's idea of a heap. and is essentially a wrapper
/// with some bookkeeping info along with supported memory types.
/// Think of this as an otherwise unstructured blob of page-sized virtual chunks
/// Each heap gets exactly 1 Vulkan device heap bound to it, which it will then suballocate until it's exhausted
const Heap = struct {
    const VulkanAllocationPool = std.heap.MemoryPoolExtra(GPUBlock, .{
        .growable = false,
    });

    pages: VulkanAllocationPool,
    page_size: usize,


    /// How big/how many pages should there be for this heap??? 
    /// We mostly care about usage as it relates to size (or available budget)
    /// to the application.
    /// Note that this is more of an estimate then anything else, 
    /// Vulkan allocations won't exactly match pages often, however the minimum allocation
    /// size will be for individual pages.
    fn deterimineVirtualMemProps(budget: *const api.DeviceMemoryBudget) struct {usize, usize} {
        //TODO: I might consider using 2 separate heurstics depending on whether the Budget query extension is avialable
    }

    pub fn init(heap_budget: *const api.DeviceMemoryBudget, allocator: std.mem.Allocator) Error!Heap {
        const page_size, const max_pages = deterimineVirtualMemProps(heap_budget);

        return Heap{
            // I distinguish host (app-side CPU) and GPU allocation failures,
            // cuz otherwise shit gets confusing
            .pages = VulkanAllocationPool.initPreheated(allocator, max_pages) catch {
                return error.HostOutOfMemory;
            },
            .page_size = page_size,
            .break_limit = 0,
        };
    }

    /// Allocate new memory blocks. This either increases the break limit of an existing GPU block
    /// or allocates a new one
    pub fn grow(self: *Heap, reqs: vk.MemoryRequirements) void {
    }
};

pub const Error = error{
    HostOutOfMemory,
    DeviceOutOfMemory,
    NoMatchingHeap,
    // InvalidConfiguration, This'll be handled with asserts in debug
};

/// Map of available memory heaps (pools)
/// This is just an array with extra steps
const HeapMap = struct {
    heaps: []Heap,
    /// prefills heaps with pools of handles
    pub fn init(layout: *const api.DeviceMemoryLayout, allocator: std.mem.Allocator) Error!HeapMap {
        const num_heaps = layout.memory_heaps.len;

        const heaps = allocator.alloc(Heap, num_heaps) catch
            return error.HostOutOfMemory;

        for (heaps, layout.memory_heaps) |*heap, props| {
            heap.* = try heap.init(props.index, props.supported_props);
        }
    }

    pub fn get(self: *HeapMap, index: usize) Error!*Heap {
        if (index >= self.heaps.len) return error.NoMatchingHeap;
        return self.heaps[index];
    }
};

/// Manages top-level handles to instantiated
/// heap allocations for all included memory types
/// This is one of the few allocators that directly allows for memory configuration
/// rather than just having a predefined configuration specified at initialization time.
/// Also, I don't really think this'll fit into a standard interface
///
/// ## For Users:
/// * DO NOT use this for general purpose allocations. Think of this as the OS syscall heap allocator,
///   except worse.
/// * Every single allocation will likely consume a huge chunk of memory and likely result in 
///   a separate GPU allocation, which vulkan no likey.
/// * Rather, it is better to use this as a parent allocator for a more efficient child allocator.
///   This ensures the giant memory blob is better utilized then being wasted on a single 24 byte 
///   uniform buffer.
pub const VirtualAllocator = struct {
    allocator: std.mem.Allocator,

    dev_mem_layout: *const api.DeviceMemoryLayout,
    di: *const api.DeviceInterface,
    heaps: HeapMap,

    /// Doesn't actually do much rn but could anticipatorially do some ahead-of-time heap allocation
    pub fn init(ctx: *const Context, allocator: std.mem.Allocator) Error!VirtualAllocator {
        const layout = ctx.env(.dev_mem_layout);
        return VirtualAllocator{
            .allocator = allocator,
            .di = ctx.env(.di),
            .dev_mem_layout = layout,
            .heaps = HeapMap.init(layout),
        };
    }

    pub fn allocate(self: *VirtualAllocator, config: AllocationConfig) Error!Allocation {
        const resolved_config = config.flatten();
        const reqs = resolved_config.mem_reqs;
        const props = resolved_config.mem_props;

        const type_index: u32 = self.dev_mem_layout.findCompatibleHeapIndex(reqs, props) orelse return Error.NoMatchingHeap;

        var chosen_heap = try self.heaps.get(type_index);

        const new_mem = try chosen_heap.grow(reqs);
    }
};

// Vulkan Memory Types and Heaps:
// * There are memory heaps, which generally map to GPU/CPU physical memory
//    * Each heap has a fixed budget of total bytes, which may differ from the total memory available in said heap
// * Memory types, are bound to a heap, and offer a view into said memory
//   with specific properties, backed by the implementation most likely.
//    * These properties will be backed by the implementation, supporting things
//      like GPU-Host coherency, or requireing cache flush/invalidtion operations.
// Rather then just having user specify the memory types they'd like for an allocation,
// Users will give hints that better inform their actual usage, such as whether to use linear allocation,
// or to ensure the memory is host-mappable.

// pub fn fucc() !void {
//     const ctx: *const Context = Context.MagicallyInit(yadda yadda);
//
//     // ....Other initialization shit...
//
//     // Way 1: Just specifying memory directly
//     // Assume Yadda Yadda means correct memory/init configuration
//     // ctx.mem is a per-context "configurable" allocator as stated
//     const buf_memory = try ctx.mem.allocate(yadda yadda);
//     const my_buffer = VertexBuffer.init(ctx, buf_memory, .{yadda yadda});
//
//     // This allows users to do, for example
//     // pick a specific existing allocator or create their own
//
//     // Uses the same "AllocationConfig" to find a compatible allocator
//     // ALSO: var my_way_better_allocator = GPUStackAllocator.init(some_other_memory_block).allocator();
//     var my_way_better_allocator = ctx.mem.findAllocator(AllocationConfig{}) orelse @panic("Reinvented the wheel too hard");
//     const mem2 = try my_way_better_allocator.allocate(.{yadda yadda});
//     const my_buffer2 = VertexBuffer.init(ctx, mem2, .{yadda yadda});
//
//     // Way 2: Asking the buffer and finding a graceful compromise
//     var required: AllocationConfig = VertexBuffer.getRequiredPropertiesFor(.{some_use_case});
//     // Can fail if the buffer has a hard requirement for something
//     // (OPTIONAL)
//     try required.unify(AllocationConfig{my_extra_properties});
//
//     const mem3 = try ctx.mem.allocate(required);
//     const my_buffer3 = VertexBuffer.init(ctx, mem3, .{yadda yadda});
//
//
//     // Way 3: Automated:
//     const my_buffer4 = try VertexBuffer.initAlloc(ctx, .{yadda yadda});
// }
