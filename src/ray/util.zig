pub fn asCString(rep: anytype) [*:0]const u8 {
    return @as([*:0]const u8, @ptrCast(rep));
}

pub fn emptySlice(comptime T: type) []T {
    return &[0]T{};
}

pub fn asManyPtr(comptime T: type, ptr: *const T) [*]const T {
    return @as([*]const T, @ptrCast(ptr));
}

// TODO: Basic logging function that displays enclosing type for member functions
pub const Logger = struct {};
