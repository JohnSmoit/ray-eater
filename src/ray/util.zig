

pub fn asCString(rep: anytype) [*:0]const u8 {
    return @as([*:0]const u8, @ptrCast(rep));
}
