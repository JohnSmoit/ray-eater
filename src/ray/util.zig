pub fn asCString(rep: anytype) [*:0]const u8 {
    return @as([*:0]const u8, @ptrCast(rep));
}

// TODO: Basic logging function that displays enclosing type for member functions
pub const Logger = struct {};
