const common = @import("common");
const vk = @import("vulkan");
const std = @import("std");

/// Just a thin wrapper over a VkDeviceMemory with some extra crap
/// Think of this as an individual device memory, the only real difference is that
/// it supports suballocations on a less granular page size.
/// This is more of a low-level arena, which can grow but expects
/// free chunks to be managed by a higher level system.
/// Deinitiialize it to destroy the associated DeviceMemory
pub const GPUBlock = struct {
    const PageRange = struct {
        h_block: common.Handle(GPUBlock),
        offset: u32,
        count: u32,
    };

    parent_heap: Heap,
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
    pub fn init(heap: Heap, page_count: u16) GPUBlock {
    }
    
    /// Increase size of GPU block, essentially allocating more of the given heap
    /// to the application process
    pub fn grow(self: *GPUBlock, amount: usize) Error!Allocation {

    }

    /// Allocate a new page range if space currently exists in the given GPU block.
    /// This will only be called by heaps if they don't have a free range of compatible
    /// pages
    pub fn allocatePageRange(self: *GPUBlock, count: usize) PageRange {
    }
    
    pub fn deinit(self: *GPUBlock) void {
    }
};

/// Individual memory heap,
/// This maps cleanly onto vulkan's idea of a heap. and is essentially a wrapper
/// with some bookkeeping info along with supported memory types.
/// Think of this as an otherwise unstructured blob of page-sized virtual chunks
/// Each heap gets exactly 1 Vulkan device heap bound to it, which it will then suballocate until it's exhausted
const HeapData = struct {
    const VulkanBlockPool = common.MemoryPool(GPUBlock, .{
        .IndexType = u16,
    });

    const GPUBlockHandle = VulkanBlockPool.Handle;

    pages: VulkanBlockPool,
    page_size: usize,
    block_size: usize,


    /// How big/how many pages should there be for this heap??? 
    /// We mostly care about usage as it relates to size (or available budget)
    /// to the application.
    /// Note that this is more of an estimate then anything else, 
    /// Vulkan allocations won't exactly match pages often, however the minimum allocation
    /// size will be for individual pages.
    fn deterimineVirtualMemProps(budget: *const api.DeviceMemoryBudget) struct {usize, usize, usize} {
        //TODO: I might consider using 2 separate heurstics depending on whether the Budget query extension is avialable
    }

    pub fn init(heap_budget: *const api.DeviceMemoryBudget, allocator: std.mem.Allocator) Error!HeapData {
        const page_size, 
        const max_pages, 
        const block_size = deterimineVirtualMemProps(heap_budget);

        return HeapData{
            // I distinguish host (app-side CPU) and GPU allocation failures,
            // cuz otherwise shit gets confusing
            .pages = VulkanBlockPool.initPreheated(
                allocator, 
                heap_budget.size / block_size,
            ) catch {
                return error.HostOutOfMemory;
            },
            .page_size = page_size,
            .block_size = block_size,
        };
    }

    /// Allocate new memory blocks. This either increases the break limit of an existing GPU block
    /// or allocates a new one
    pub fn grow(self: *HeapData, reqs: vk.MemoryRequirements) Error!GPUBlock.PageRange {
    }

    pub fn shrink(self: *HeapData, alloc: Allocation) void {
    }
};

/// Map of available memory heaps (pools)
/// This is just an array with extra steps
pub const HeapMap = struct {
    const HeapPool = common.MemoryPool(HeapData, .{
        .IndexType = u8,
    });

    pub const Handle = HeapPool.Handle;
    heaps: HeapPool,
    /// prefills heaps with pools of handles
    pub fn init(heaps: []const vk.MemoryHeap, types: []const vk.MemoryType, allocator: std.mem.Allocator) Error!HeapMap {
        const num_heaps = layout.memory_heaps.len;

        const heaps = HeapPool.init(num_heaps, allocator) catch
            return error.HostOutOfMemory;

        for (heaps.items, layout.memory_heaps) |*heap, props| {
            heap.* = try HeapData.init(props.index, props.supported_props);
        }

        return HeapMap{
            .heaps = heaps,
        };
    }

    pub fn getHeapForMemoryType(self: *HeapMap, type_index: usize) Error!Heap {

    }

    pub fn getHeapByIndex(self: *HeapMap, mem_index: usize) Error!Heap {
        if (mem_index >= self.heaps.items.len) return error.NoMatchingHeap;
        return self.heaps.handle(mem_index);
    }
};
