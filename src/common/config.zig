//! Configurations and stuff but cooler

const std = @import("std");
const util = @import("common.zig").util;

fn validateProfiles(
    comptime T: type, 
    comptime Hint: type,
) std.builtin.Type.Enum {
    const pinfo = @typeInfo(T);
    if (!pinfo == .@"enum")
        @compileError("Invalid profile listing enum: " ++
            @typeName(T) ++ " for config type: " ++ @typeName(Hint));

    return pinfo.@"enum";
}

fn validateDef(
    comptime T: type,
    comptime def: anytype,
    comptime Hint: type,
) void {
    const info = @typeInfo(@TypeOf(def));

    switch (info) {
        .@"struct" => |*s| {
            const pinfo = @typeInfo(T).@"enum";
            for (pinfo.fields) |fld| {
                if (util.tryGetField(s, fld.name)) {
                    @compileError("Profile def missing field: " ++
                        fld.name ++ " for config type: " ++ @typeName(Hint));
                }
            }
        },
        else => @compileError("Invalid profile def struct: " ++
            @typeName(T) ++ " for config type: " ++ @typeName(Hint)),
    }
}


pub fn ConfigurationRegistry(
    /// ConfigType can be any struct
    comptime ConfigType: type,
    /// Profiles must be a packed, non-sparse enum, (preferably human readable)
    comptime Profiles: type,
    /// profile_defs must be an anonymous struct literal
    /// whose fields are named after the "Profile" enum fields
    /// with an additional field called "Default" for the default configuration
    /// Values can either be valid instances of the configuration struct type,
    /// or one of the provided parameterization helper types
    comptime profile_defs: anytype,
) type {
    const profile_info = validateProfiles(Profiles, ConfigType);
    validateDef(Profiles, profile_defs, ConfigType);

    const profiles_len = profile_info.fields.len;
}

pub fn Parameterized(
    comptime instance: anytype,
    comptime params: anytype,
) @TypeOf(instance) {}

fn ResolverFn(comptime T: type) type {}

pub const ParameterDef = struct {};

pub fn Parameter(
    comptime T: type,
    comptime field_name: [:0]const u8,
    comptime resolver: anytype,
) ParameterDef {}
