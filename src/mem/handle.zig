const std = @import("std");

pub const HandleType = enum {
    Single,
    Multi,
};
/// generic type-erased handle
/// contains the minimal amount of data required to work, but no higher-level functionality
/// To ensure safety, don't initialize these from scratch,
pub const OpaqueHandle = struct {
    // value is always treated in a type-erased manner,
    // gets and sets, as well as wrapped API functions will cast this as the appropriate
    // type
    // This is sort of not safe, so I'll provide debug functionality to ensure that handles
    // are valid whenever they're acquired.
    value: *anyopaque,

    type_data: union(HandleType) {
        Single,
        Multi: usize,
    },
};


const assert = std.debug.assert;
/// Typed handle, with support for derefrence
pub fn Handle(comptime T: type) type {
    return struct {
        const Self = @This();
        base: OpaqueHandle,
            
        // TODO: Implement this so that you can't just pass any opaque handle --
        // It needs to be guarunteed that the handle bound is of a compatible type
        // -- TO do that, I'll need to implement at least some of the type-scoped allocators
        // first
        pub fn bindOpaque(self: *Self) void {
        }
        
        // these are ease-of-use pseudo-dereference operators
        pub fn get(self: *const Self) *const T {
            assert(self.base.type_data == .Single);
            return @as(*const T, @ptrCast(self.base.value));
        }

        pub fn getMut(self: *Self) *T {
            assert(self.base.type_data == .Single);
            return @as(*T, @ptrCast(self.base.value));
        }

        pub fn getMulti(self: *const Self) []const T {
            assert(self.base.type_data == .Multi);
            return @as([*]const T, @ptrCast(self.base.value))[0..self.base.type_data.Multi];
        }

        pub fn getMultiMut(self: *Self) []T {
            assert(self.base.type_data == .Multi);
            return @as([*]T, @ptrCast(self.base.value))[0..self.base.type_data.Multi];
        }
    };
}
