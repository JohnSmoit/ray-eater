const std = @import("std");
pub fn asCString(rep: anytype) [*:0]const u8 {
    return @as([*:0]const u8, @ptrCast(rep));
}

pub fn emptySlice(comptime T: type) []T {
    return &[0]T{};
}

//FIXME: This is due for a BIG REFACTOR COMING SOON
// (because it is much worse than just &.{} which I Didn't know was a thing oops.
pub fn asManyPtr(comptime T: type, ptr: *const T) [*]const T {
    return @as([*]const T, @ptrCast(ptr));
}

//FIXME: This is due for a BIG REFACTOR COMING SOON
// (because it is much worse than just &.{} which I Didn't know was a thing oops.
// funilly enough, &.{1, 2, 3} is shorter than span(.{1, 2, 3}). I just don't 
// like reading docs + idk how.
pub fn span(v: anytype) [] @TypeOf(v[0]) {
    const T = @TypeOf(v[0]);
    comptime var sp: [v.len] T = undefined;
    for (v, 0..) |val, index| {
        sp[index] = val;
    }

    return sp[0..];
}

const StructInfo = std.builtin.Type.Struct;
const StructField = std.builtin.Type.StructField;
const Function = std.builtin.Type.Fn;

// Reflection Stuff
pub fn tryGetField(info: *StructInfo, name: []const u8) ?*StructField {
    for (info.fields) |*fld| {
        if (std.mem.eql(u8, fld.name, name) == .eq) {
            return fld;
        }
    }

    return null;
}

pub fn signatureMatches(a: *const Function, b: *const Function) bool {
    if (a.params.len != b.params.len) return false;
    for (a.params, b.params) |p1, p2|
        if (p1.type != p2.type) return false;

    if (!a.calling_convention.eql(b)) return false;
    return true;
}
