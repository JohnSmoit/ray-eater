//! TODO: Merge this into the common directory
//! Most of this is completely unused and useless, so
//! only a bit of this iwll be included...
const std = @import("std");
const builtin = @import("builtin");
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
pub fn span(v: anytype) []@TypeOf(v[0]) {
    const T = @TypeOf(v[0]);
    comptime var sp: [v.len]T = undefined;
    for (v, 0..) |val, index| {
        sp[index] = val;
    }

    return sp[0..];
}

const StructInfo = std.builtin.Type.Struct;
const StructField = std.builtin.Type.StructField;
const Function = std.builtin.Type.Fn;

// Reflection Stuff
pub fn tryGetField(info: *const StructInfo, name: []const u8) ?*const StructField {
    for (info.fields) |*fld| {
        if (std.mem.eql(u8, fld.name, name)) {
            return fld;
        }
    }

    return null;
}

pub fn fnSignatureMatches(
    comptime A: type,
    comptime B: type,
) bool {
    const info_a = if (@typeInfo(A).@"fn") @typeInfo(A).@"fn" else return false;
    const info_b = if (@typeInfo(B).@"fn") @typeInfo(B).@"fn" else return false;

    if (info_a.params.len != info_b.params.len) return false;

    for (info_a.params, info_b.params) |a, b| {
        if (!std.meta.eql(a, b)) return false;
    }

    return true;
}

/// returns the percentage of a number
/// should work for all numeric types
pub fn pct(num: anytype, percentage: @TypeOf(num)) @TypeOf(num) {
    return @divTrunc(num * percentage, 100);
}

const BasicMemUnits = enum(usize) {
    Bytes,
    Kilobytes,
    Megabytes,
    Gigabytes,
};

/// Obviously, val should be numerical, but should
/// otherwise work with integral and floating points,
/// illegal divisions notwithstanding.
pub inline fn transformMemUnits(comptime from: BasicMemUnits, comptime to: BasicMemUnits, val: anytype) @TypeOf(val) {
    const ValueType = @TypeOf(val);
    const info = @typeInfo(ValueType);

    var a: ValueType = 1;
    var b: ValueType = 1;

    for (0..@intFromEnum(to)) |_| {
        a *= 1024;
    }
    for (1..@intFromEnum(from)) |_| {
        b *= 1024;
    }

    if (info == .int) {
        return @divFloor(a, b) * val;
    } else {
        const fnum: ValueType = @floatFromInt(a);
        const fden: ValueType = @floatFromInt(b);

        return (fnum / fden) * val;
    }
}

pub inline fn megabytes(val: anytype) @TypeOf(val) {
    return transformMemUnits(.Megabytes, .Bytes, val);
}

pub inline fn assertMsg(ok: bool, comptime msg: []const u8) void {
    if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) {
        if (!ok) {
            @panic("Assertion failed: " ++ msg);
        }
    }
}

pub fn signatureMatches(a: *const Function, b: *const Function) bool {
    if (a.params.len != b.params.len) return false;
    for (a.params, b.params) |p1, p2|
        if (p1.type != p2.type) return false;

    if (!a.calling_convention.eql(b)) return false;
    return true;
}

///TODO: Param for ordering fields in the bitset,
/// which I don't really need now, but could be useful later
pub fn EnumToBitfield(comptime E: type) type {
    const e_info = @typeInfo(E);
    const default_value: bool = false;

    if (e_info != .@"enum")
        @compileError("Invalid type: " ++ @typeName(E) ++ " must be an enum to convert to bitfield");

    comptime var bit_fields: []const StructField = &.{};
    for (e_info.@"enum".fields) |fld| {
        bit_fields = bit_fields ++ &[_]StructField{.{
            .type = bool,
            .alignment = 0,
            .is_comptime = false,
            .default_value_ptr = &default_value,
            .name = fld.name,
        }};
    }

    const InnerBitfield = @Type(.{.@"struct" = std.builtin.Type.Struct{
        .decls = &.{},
        .fields = bit_fields,
        .layout = .@"packed",
        .is_tuple = false,
    }});

    const BackingInt = @typeInfo(InnerBitfield).@"struct".backing_integer orelse 
        @compileError("Too many fields in enum: " ++ @typeName(E));

    return struct {
        pub const EnumType = E;
        pub const Bitfield = InnerBitfield;
        const EnumBitfield = @This();

        val: Bitfield = .{},
        pub fn initPopulated(vals: []const EnumType) EnumBitfield {
            var new: EnumBitfield = .{};

            for (vals) |v| {
                new.set(v);
            }

            return new;
        }

        pub fn has(bits: EnumBitfield, val: EnumType) bool {
            var dumbass_copy = bits.val;
            const bit: usize = @intFromEnum(val);
            const int_val: BackingInt = @as(*BackingInt, @ptrCast(@alignCast(&dumbass_copy))).*;
            return (int_val >> @as(u4, @intCast(bit))) & 0x1 != 0;
        }

        pub fn set(bits: *EnumBitfield, val: EnumType) void {
            const bits_as_int = @as(*BackingInt, @ptrCast(@alignCast(&bits.val)));
            const bit = @intFromEnum(val);
            bits_as_int.* |= @as(BackingInt, 1) << @as(u4, @intCast(bit));
        }
    };
}
