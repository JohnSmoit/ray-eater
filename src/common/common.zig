const std = @import("std");
const assert = std.debug.assert;

const h = @import("handle.zig");
pub const Handle = h.Handle;
pub const OpaqueHandle = h.OpaqueHandle;

// these resemble std's pools, but they have intrinsic support for handle
// indexing
pub const ObjectPool = @import("object_pool.zig").ObjectPool;

pub const config = @import("config.zig");
pub const util = @import("util.zig");

/// This is cursed as hell..
/// Returns a unique identifier for any type at comptime or runtime
/// https://github.com/ziglang/zig/issues/19858#issuecomment-2094339450
pub const TypeId = usize;
pub fn typeId(comptime T: type) TypeId {
    // Uhhh....
    return @intFromError(@field(anyerror, @typeName(T)));
}



fn APIFunctionType(func: anytype) type {
    const T = @TypeOf(func);
    _ = T;
}

// Type Ids shoudl only be conditionally compiled
// in a runtime safety build, otherwise all type ID checking should
// be a no-op
pub const AnyPtr = struct {

    ptr: *anyopaque,
    id: TypeId,

    pub fn from(comptime T: type, ptr: *T) AnyPtr {
        return .{
            .ptr = ptr,
            .id = typeId(T),
        };
    }
    
    /// Used if the underlying type is already a pointer
    pub fn fromDirect(comptime T: type, ptr: T) AnyPtr {
        return .{
            // Only reason const cast is here is because I'm probably gonna toss this entire type
            .ptr = @constCast(ptr),
            .id = typeId(T),
        };
    }

    pub fn get(self: AnyPtr, comptime T: type) *T {
        assert(self.id == typeId(T));
        return @as(*T, @ptrCast(@alignCast(self.ptr)));
    }
};

/// # Overview:
/// This just remaps the first argument from a pointer to the DATA
/// type to a pointer to the API proxy type, with some minimal surrounding logic
/// in the wrapping function's body
///
/// ## Notes:
/// Automagically handles multi-application of the internal function based 
/// on the number of objects referenced by the handle.
/// FIX: This is seeming to be disgusting to implement per-spec here
/// Need an alternative method, either constraining type signatures
/// or just not automating API function binding since there isn't that much extra code
/// I need right now
pub fn APIFunction(func: anytype) APIFunctionType(func) {
}


comptime {
    _ = @import("config.zig");
    _ = @import("object_pool.zig");
}
