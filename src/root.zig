pub const Context = @import("context.zig");

// Low-Level vulkan wrappers
pub const api = @import("api/api.zig");

// Linear algebra math
pub const math = @import("math.zig");

//TODO: replace the shitty utils with common
pub const common = @import("common");
pub const util = @import("util.zig");

// Resource manager NOTE: (not sure if this should be exported tbh)
pub const res = @import("resource_management/res.zig");

// imports for testing
comptime {
    _ = @import("resource_management/pool_allocator.zig");
    _ = @import("resource_management/registry.zig");
}
