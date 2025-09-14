//! A pool represents a logical view into memory, and can be generated from any valid allocation.
//! Contains metadata about the allocation it references (and unlike allocations, this persists
//! even when not in debug mode) along with a list of host-allocated control blocks
//! for bookkeeping information regarding the memory allocation. 

const common = @import("common");
const std = @import("std");

const allocation = @import("allocation.zig");

const AllocationData = allocation.AllocationData;
const Allocation = allocation.Allocation;
const ReifiedAllocation = allocation.ReifiedAllocation;

const ControlBlockTable = std.AutoHashMap(common.TypeId, ControlBlockHeader);
const AllocationTable = common.ObjectPool(AllocationData, .{});

const prealloc_size: usize = 64;
const SrcAllocationList = std.SegmentedList(ReifiedAllocaiton, prealloc_size);

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
src_allocations: SrcAllocationList, 

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
