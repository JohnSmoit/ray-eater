const std = @import("std");
const common = @import("common.zig");

const AnyPtr = common.AnyPtr;

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
    value: AnyPtr,

    type_data: union(HandleType) {
        Single,
        Multi: usize,
    },
};

const assert = std.debug.assert;

pub const Config = struct {
    index_bits: u16 = 32,
    generation_bits: u16 = 32,
};


/// Typed handle, with support for derefrence
pub fn TypedHandle(comptime T: type, comptime config: Config) type {
    const IndexType: type = std.meta.Int(.unsigned, config.index_bits);
    const GenerationType: type = std.meta.Int(.unsigned, config.generation_bits);

    return packed struct {
        const UnderlyingType = T;
        const Handle = @This();

        index: IndexType = 0,
        gen: GenerationType = 0,

        pub fn bind(handle: *Handle, index: IndexType) void {
            handle.index = index;
            handle.gen += 1;
        }
    };
}
