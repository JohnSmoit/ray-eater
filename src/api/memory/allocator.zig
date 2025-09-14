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
const api = @import("../api.zig");

const Context = @import("../../context.zig");

const allocation = @import("allocation.zig");

pub const Error = error{
    HostOutOfMemory,
    DeviceOutOfMemory,
    NoMatchingHeap,
    // InvalidConfiguration, This'll be handled with asserts in debug
};


const Allocation = allocation.Allocation;
const ReifiedAllocation = allocation.ReifiedAllocation;


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

const ResourceLayoutType = enum(u1) {
    /// The resource is expected to have a linear,
    /// (i.e a contiguous array) layout, which concerns buffers.
    /// This does not imply that the actual user-defined layout of a buffer needs to be a specific way,
    /// moreso that the resource won't use any vulkan driver supported layout options.
    Linear,
    /// The resource is expected to have a varying/vulkan
    /// supported layout. This applies mostly to images
    Optimal,
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

const DedicatedAllocationPolicyBits = enum(u2) {
    Force,
    Disallow,
    Unspecified,
};

pub const AllocationConfig = packed struct {
    pub const GeneralFlags = packed struct {
        ///General stuff
        /// Whether or not the best fit should be selected in case a perfect
        /// allocator match isn't found
        best_fit: bool = true,

        /// Relevant allocation is promised but may not actually be allocated until
        /// the allocation is first accessed
        /// NOTE: Uuuhhh, I gotta make sure this actually guaruntees a valid memory allocation
        /// when its needed
        lazy: bool = false,

        /// Force the allocator to perform a dedicated
        /// VkAllocateMemory specifically for this allocation (renders most configuration moot)
        dedicated_alloc_policy: DedicatedAllocationPolicyBits = .Unspecified,
    };
    
    /// This is the final layout of configuration
    /// required for the allocation algorithm to actually specify allocation
    pub const Resolved = packed struct {
        mem_props: vk.MemoryPropertyFlags,
        mem_reqs: vk.MemoryRequirements,
        general_flags: GeneralFlags,
        resource_type: ResourceLayoutType,
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

    /// Whether or not the allocation is expected to be used 
    /// Defaults to null in which case the resource should be explicitly specified
    /// Unfortunately, vulkan has very specific requirements on how memory between buffers
    /// and images ought to be laid out so the allocator will need at least some knowledge of 
    /// what the allocation will actually be used for.
    resource_type: ?ResourceLayoutType = null,

    /// Structure hints
    /// This controls whether or not to use a structured memory pool
    /// based on given parameters
    structure_hints: StructureHints = .{},

    general: GeneralFlags = .{},

    /// Flattens all nullable values and optional configuration parameters
    /// into a common resolved layout.
    /// This tends to ignore certain information 
    /// in order to generate concrete allocation parameters so further config processing is
    /// usually done by the configurable allocator beforehand to resolve which allocator to use
    /// This is moreso "stage 2" resolution as defined in the spec
    pub fn flatten(self: *const AllocationConfig) Resolved {
        _ = self;
        return undefined;
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
/// * Recommended not to instance this yourself, as every context's memory manager will come with
///   an instanced version
/// * This allocator uses an extremely basic algorithm which allocates and frees large blocks of memory
///   with little regard for fragmentation, making it a poor choice anyways for a general-purpose allocator
pub const VirtualAllocator = struct {
    /// Env's can be manually initialized if you don't want to 
    /// go through the entire context init schtick
    pub const Env = Context.EnvSubset(.{.mem_layout, .di});

    allocator: std.mem.Allocator,
    env: Env,

    // Free list tracking which unfortunately can't be in-place sigh


    /// Doesn't actually do much rn but could anticipatorially do some ahead-of-time heap allocation
    pub fn init(
        env: Env, 
        allocator: std.mem.Allocator,
    ) Error!VirtualAllocator {
        return VirtualAllocator{
            .allocator = allocator,
            .env = env,
        };
    }

    /// Retrieves or creates a bookkeeping entry 
    /// to a given vulkan pool with specific properties (caller must provide pool)
    pub fn bind(self: *VirtualAllocator, pool: *VulkanPool) Error!void {
    }

    /// NOTE: This allocator doesn't support best fit re-indexing, 
    /// that happens at a higher level.
    pub fn allocate(self: *VirtualAllocator, config: AllocationConfig) Error!Allocation {
        _ = self;
        _ = config;

        return undefined;
    }
    
    /// This version returns a reified handle to the allocation table
    /// which is essentially combined data and API along with pointer to the backing pool
    /// for that classic OOP feel (even if it's all a lie)
    pub fn allocateReified(self: *VirtualAllocator, config: AllocationConfig) Error!ReifiedAllocation {
        _ = self;
        _ = config;

        return undefined;
    }

    pub fn free(self: *VirtualAllocator, mem: Allocation) void {
        _ = self;
        _ = mem;
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

const debug = std.debug;
