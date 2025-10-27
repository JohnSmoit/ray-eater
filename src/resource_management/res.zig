const common = @import("common");

pub const Registry = @import("registry.zig");
pub const ResourceManager = @import("resource_manager.zig");
pub const APIFactory = @import("factory.zig").APIFactory;

/// Provides a single source of truth for normal object pools,
/// rather then just spamming the same (potentially complex) definition 
/// everywhere
pub fn StandardObjectPool(comptime T: type) type {
    return common.ObjectPool(T, .{});
}

comptime {
    _ = @import("factory.zig");
}
