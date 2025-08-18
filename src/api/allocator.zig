//! Vulkan-specific allocator for giving user control over host and device-side allocations.
//! Of course, the standard zig allocation interface is great but it's usage doesn't 
//! fit well into device-side memory allocations, so we have this.
//!
//! I will do my best to keep the implementation of this allocator be as in-line as possible
//! to the standard memory allocation interface (if I can I will support creating
//! std.mem.Allocators).

