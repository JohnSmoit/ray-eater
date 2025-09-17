//! Contrary to popular belief, this is not a pool allocator, it is in fact
//! a TLSF allocator in disguise!!!!!!!! >:) \_O_O_/
//! Additionally, this acts as the main virtualizer for raw GPU 
//! memory obtained by the heap. Unlike raw heap allocations, this does
//! a better job fitting allocation requests to sanely proportioned memory blocks
//! in the respective memory type and is provided by the VirtualAllocator for user
//! allocation. 
//!
//! Additionally, allocation algorithms store their bookkeeping data here,
//! to facilitate division of responsibility between algorithm and nasty
//! vulkan memory type handling. In this way an algorithm can just get their 
//! respective control block and do stuff as normal.
//!
//! Do note, while a TLSF allocator gives great (near linear) performance
//! for small to large-ish sized allocations, users will likely still want to
//! use different allocation algorithms for a whole host of reasons, with this 
//! (or a dedicated allocation) as the source for all that because of the lower
//! overall fragmentation. Examples include linear arena or stack allocators,
//! other free lists, or some form of buddy allocator, each of which
//! has it's own place where it would be best utilized.
//!
//! Honestly, the filthy casual can just get away with using the virtual allocator
//! for most cases tho...

const common = @import("common");
const std = @import("std");

const allocation = @import("allocation.zig");

const DeviceMemoryBlock = @import("DeviceMemoryBlock.zig");

const AllocationData = allocation.AllocationData;
const Allocation = allocation.Allocation;
const ReifiedAllocation = allocation.ReifiedAllocation;

const ControlBlockTable = std.AutoHashMap(common.TypeId, ControlBlockHeader);
const AllocationTable = common.ObjectPool(AllocationData, .{});


// somewhat arbitrarily chosen for 64-bit systems
// with respect to what one might expect for GPU heap sizes 
// (which are generally not more than 64 gigs)
const exp_index_size: usize = @typeInfo(usize).int.bits;
const linear_index_size: usize = 8;


// Do note that the control block for the VulkanPool allocator
// can in fact be determined entirely at compile time using just system
// parameters for word sizes and a bit of heuristics...
// NOTE: FUTURE ME
const LinearControlBlock = struct {
    free_list: std.SegmentedList(AllocationData, linear_index_size),
    size_mapping: std.IntegerBitSet(usize),
};

const ExponentControlBlock = std.SegmentedList(
    DeviceMemoryBlock, 
    exp_index_size,
);

const Pool = @This();


const Error = error {
    OutOfMemory,
};

const ControlBlockHeader = struct {
    algorithm_type: common.TypeId,
    p_control: *anyopaque,
};

// arraylists don't play nice with arenas
control_blocks: ControlBlockTable,
control_arena: std.heap.ArenaAllocator,

// TODO: should be able to specify handles in the args
// since just guessing here is a pain
// (luckily the partition bit works out in this case)
allocation_table: AllocationTable,
pool_blocks: SrcAllocationList, 

/// This is just to maintain an invariant for additional allocations
/// Specifically that contiguous memory ranges ought to be part of the same
/// dedicated allocation. Since this is not true in rare cases on its own, 
/// I provide a table
/// in order to maintain bounded coalescence of contiguous memory ranges.
///
/// NOTE: Thinking of dropping this in release builds once I'm sure consuming code
/// maintains the invariant properly.
base_memory_handles: std.SegmentedList(vk.DeviceMemory, exp_index_size);

type_index: u32,

pub fn init(allocation: ReifiedAllocation, host_allocator: std.mem.Allocator) Error!Pool {
    var arena = std.heap.ArenaAllocator.init(host_allocator),
    errdefer arena.deinit();

    var src_allocations = SrcAllocationList{};
    errdefer src_allocations.deinit();

    var control_blocks = try ControlBlockTable.init(host_allocator);
    errdefer control_blocks.deinit();

    const type_index = allocation.get().meta.type_index;

    (src_allocations.addOne() catch unreachable).* = allocation;
    return Pool{
        .control_blocks = control_blocks,
        .control_arena  = arena,
        .type_index = type_index,
        
        .src_allocations  = src_allocations,
        .allocation_table = try AllocationTable.initPreheated(
            arena.allocator(), 
            512,
        ),
    };
}

/// Technically, we could just get away with updating bookeeping information ad hoc
/// since allocations are just offsets into a memory blob.
pub fn extend(pool: *Pool, new_allocation: ReifiedAllocation) Error!Pool {
    const new_allocation = src_allocations.addOne();
}

/// Most allocation algorithms will just call this when binding a memory pool
/// This can also allocate new control blocks if a new algorithm is used
/// Expects the type to have a control block nested as a declaration
pub fn getControlBlock(
    pool: *Pool, 
    comptime AlgorithmType: type, 
    inst: *const AlgorithmType
) Error!*AlgorithmType {
    if (!std.meta.hasDecl(AlgorithmType, "ControlType")) 
        @compileError("AlgorithmType must have ControlType decl to manage bookkeeping");
    const ControlBlock = AlgorithmType.ControlBlock;


}

pub fn deinit(pool: *Pool) void {
}

// This is the class you want to access private form shit
