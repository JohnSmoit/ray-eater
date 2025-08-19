//! Configurations and stuff but cooler

const std = @import("std");
const util = @import("common.zig").util;

fn validateProfiles(
    comptime T: type,
    comptime Hint: type,
) std.builtin.Type.Enum {
    const pinfo = @typeInfo(T);
    if (pinfo != .@"enum")
        @compileError("Invalid profile listing enum: " ++
            @typeName(T) ++ " for config type: " ++ @typeName(Hint));

    return pinfo.@"enum";
}

fn validateDef(
    comptime T: type,
    comptime def: anytype,
    comptime Hint: type,
) []const std.builtin.Type.StructField {
    const info = @typeInfo(@TypeOf(def));

    switch (info) {
        .@"struct" => |*s| {
            const pinfo = @typeInfo(T).@"enum";
            for (pinfo.fields) |fld| {
                if (util.tryGetField(s, fld.name) == null) {
                    @compileError("Profile def missing field: " ++
                        fld.name ++ " for config type: " ++ @typeName(Hint));
                }
            }

            if (util.tryGetField(s, "Default") == null) {
                @compileError("Profile def missing default field " ++
                    " for config type: " ++ @typeName(Hint));
            }
        },
        else => @compileError("Invalid profile def struct: " ++
            @typeName(T) ++ " for config type: " ++ @typeName(Hint)),
    }
    return @typeInfo(@TypeOf(def)).@"struct".fields;
}

pub const ParameterDef = struct {
    OutputType: type,
    out_fld_name: [:0]const u8,
    in_fld_name: [:0]const u8,

    InputType: type,
    resolver: *const anyopaque,
};

fn ProfileDef(comptime ConfigType: type) type {
    return union(enum) {
        Valued: struct {
            PType: ?type,
            default_val: ConfigType,
            // map from field names to all resolver functions (built from param data)
            resolvers: ?std.StaticStringMap(ParameterDef),
        },
        Function,
    };
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
    const def_fields = validateDef(Profiles, profile_defs, ConfigType);

    // Extra field for the default profile
    const profiles_len = profile_info.fields.len + 1;
    const ProfileDefType = ProfileDef(ConfigType);
    comptime var profiles: [profiles_len]ProfileDefType = .{undefined} ** profiles_len;

    for (def_fields) |fld| {
        const field_index: usize = if (!std.mem.eql(u8, fld.name, "Default"))
            @intFromEnum(std.meta.stringToEnum(
                Profiles,
                fld.name,
            ) orelse unreachable)
        else
            (profiles_len - 1);

        profiles[field_index] = switch (fld.type) {
            ParameterizedProfileDef(ConfigType) => blk: {
                const parameters = @field(profile_defs, fld.name).params;

                comptime var ptype_fields: []const std.builtin.Type.StructField = &.{};
                comptime var resolvers: []const struct { []const u8, ParameterDef } = &.{};

                for (parameters) |p| {
                    ptype_fields = ptype_fields ++ [_]std.builtin.Type.StructField{.{
                        .name = p.in_fld_name,
                        .type = p.InputType,
                        .default_value_ptr = null,
                        .is_comptime = false,
                        .alignment = @alignOf(p.InputType),
                    }};

                    resolvers = resolvers ++ .{.{ p.in_fld_name, p }};
                }

                const PType = @Type(.{
                    .@"struct" = std.builtin.Type.Struct{
                        .fields = ptype_fields,
                        .decls = &.{},
                        .is_tuple = false,
                        .layout = .auto,
                    },
                });

                const default_val = @field(profile_defs, fld.name).default_val;

                break :blk ProfileDefType{ .Valued = .{
                    .PType = PType,
                    .default_val = default_val,
                    .resolvers = std.StaticStringMap(ParameterDef)
                        .initComptime(resolvers),
                } };
            },
            ConfigType => blk: {
                const default_val: ConfigType = @field(profile_defs, fld.name);

                break :blk ProfileDefType{ .Valued = .{
                    .PType = null,
                    .default_val = default_val,
                    .resolvers = null,
                } };
            },
            else => {
                //TODO: Check for a full mapping function signature later
                @compileError("Invalid profile def entry for type: " ++
                    @typeName(ConfigType));
            }
        };
    }

    return struct {
        const Self = @This();
        const profile_data: [profiles_len]ProfileDefType = profiles;
        const default_index = profiles_len - 1;
        // TODO: Check presence of fields
        // and make sure the params are a struct literal.
        fn comptimeValidate(params: anytype, index: usize) void {
            comptime {
                const params_info = @typeInfo(@TypeOf(params));
                switch (params_info) {
                    .@"struct" => {},
                    else => @compileError("Invalid parameter literal: must be struct!"),
                }

                _ = index;
            }
        }
        pub const ConfigBuilder = struct {
            underlying: ConfigType,
            pub fn extend(self: *ConfigBuilder, vals: ConfigType) *ConfigBuilder {
                inline for (@typeInfo(ConfigType).@"struct".fields) |*fld| {
                    const default_val = fld.defaultValue();
                    const in_val = @field(vals, fld.name);
                    
                    // This ensures we do not overwrite fields that are left as default values.
                    if (!std.meta.eql(default_val, in_val)) {
                        @field(
                            self.underlying,
                            fld.name,
                        ) = @field(vals, fld.name);
                    }
                }

                return self;
            }

            pub fn combine(self: *ConfigBuilder, comptime profile: Profiles, params: anytype) *ConfigBuilder {
                const other = Self.ProfileMixin(profile, params);
                return self.extend(other);
            }

            pub fn finalize(self: *const ConfigBuilder) ConfigType {
                return self.underlying;
            }
        };

        pub fn BuilderMixin(comptime profile: Profiles, params: anytype) ConfigBuilder {
            return .{
                .underlying = setFromProfileIndex(@intFromEnum(profile), params),
            };
        }

        fn setFromProfileIndex(comptime index: usize, params: anytype) ConfigType {
            const profile_def = profile_data[index];
            return switch (profile_def) {
                .Valued => |*v| blk: {
                    var val: ConfigType = v.default_val;
                    if (v.resolvers) |rmap| {
                        // PType is only null if there are no resolver methods...
                        const ptype_info = @typeInfo(v.PType orelse unreachable).@"struct";

                        inline for (ptype_info.fields) |*fld| {
                            const res = rmap.get(fld.name) orelse unreachable;
                            const in_val = @field(params, res.in_fld_name);

                            const func = @as(
                                *const fn (res.InputType) res.OutputType,
                                @ptrCast(@alignCast(res.resolver)),
                            );

                            @field(val, res.out_fld_name) = func(in_val);
                        }
                    }

                    break :blk val;
                },
                .Function => @compileError("Function-based profiles currently unsupported!"),
            };
        }

        pub fn DefaultMixin(params: anytype) ConfigType {
            return setFromProfileIndex(default_index, params);
        }

        pub fn ProfileMixin(comptime profile: Profiles, params: anytype) ConfigType {
            return setFromProfileIndex(@intFromEnum(profile), params);
        }
    };
}

fn ParameterizedProfileDef(comptime ConfigType: type) type {
    return struct {
        params: []const ParameterDef,
        default_val: ConfigType,
    };
}

pub fn Parameterized(
    comptime instance: anytype,
    comptime params: anytype,
) ParameterizedProfileDef(@TypeOf(instance)) {
    if (@typeInfo(@TypeOf(params)) != .@"struct")
        @compileError("Invalid parameterset type (must be struct) " ++
            @typeName(@TypeOf(instance)));

    const pinfo = @typeInfo(@TypeOf(params)).@"struct";
    comptime var params_list: []const ParameterDef = &.{};

    for (pinfo.fields) |fld| {
        const val = @field(params, fld.name);

        params_list = params_list ++ [_]ParameterDef{.{
            .out_fld_name = fld.name,

            .OutputType = val.OutputType,
            .InputType = val.InputType,
            .in_fld_name = val.in_fld_name,
            .resolver = val.resolver,
        }};
    }

    return .{
        .params = params_list,
        .default_val = instance,
    };
}

// fn ResolverFn(comptime T: type) type {}

// since the output field names are mapped to the left-hand side
// of an assignment, we need a temporary storage record for the rest of the data.
// This is mostly for usage ergonomics, there's no actual implementation reason
// that it has to be this way.
const IntermediateParam = struct {
    OutputType: type,
    InputType: type,
    in_fld_name: [:0]const u8,
    resolver: *const anyopaque,
};

//Parameters can be either:
// - Resolver functions which map from an input type to a config field
// - Direct mappings from input parameters to config fields
//   (in this case, "resolver" would be null.
pub fn Parameter(
    comptime T: type,
    comptime field_name: [:0]const u8,
    comptime resolver: anytype,
) IntermediateParam {
    const ResolverType = @TypeOf(resolver);
    const rinfo = @typeInfo(ResolverType);

    const InputType, const res = switch (rinfo) {
        .@"fn" => |f| blk: {
            if (f.params.len != 1)
                @compileError("Resolver functions must take a single argument");
            const input_arg = f.params[0];

            break :blk .{ input_arg.type.?, resolver };
        },
        .null => blk: {
            const Container = struct {
                pub fn noOp(in: T) T {
                    return in;
                }
            };

            break :blk .{ T, Container.noOp };
        },
        else => @compileError("resolver must be a function or null"),
    };

    return IntermediateParam{
        .OutputType = T,
        .InputType = InputType,
        .in_fld_name = field_name,
        .resolver = res,
    };
}

const testing = std.testing;

const TestBitField = packed struct {
    bit_1: bool = false,
    bit_2: bool = false,
    bit_3: bool = false,
    rest: u5 = 0,
};

const TestConfigStruct = struct {
    flags: TestBitField = .{},

    comptime_field_a: u32 = 0,
    comptime_field_b: usize = 0,
    name: []const u8 = "Unknown",

    pointer: *const usize = &larrys_num,
    writer: ?std.io.AnyWriter = null,

    pub const Profiles = enum {
        Larry,
        Harry,
        WriterBoy,
        PartialA,
        PartialB,
    };

    const larry_last_name_table = [_][]const u8{
        "Larry Larryson",
        "Larry Jerryson",
        "Larry The Lobster",
        "Larry the Platypus",
    };

    fn resolveLarryName(index: usize) []const u8 {
        return larry_last_name_table[@mod(index, larry_last_name_table.len)];
    }

    fn sideEffectyResolver(w: std.io.AnyWriter) std.io.AnyWriter {
        _ = w.write("Evil function") catch @panic("Test write failed");
        return w;
    }

    pub const larrys_num: usize = 1000;

    const Registry = ConfigurationRegistry(TestConfigStruct, Profiles, .{
        .Harry = TestConfigStruct{
            .flags = .{
                .bit_1 = true,
                .bit_2 = false,
                .bit_3 = true,
                .rest = 10,
            },
            .comptime_field_a = 100,
            .comptime_field_b = 0,
            .name = "Harry Harryson",

            .pointer = &larrys_num,
            .writer = null,
        },
        .Larry = Parameterized(TestConfigStruct{
            .flags = .{},
            .comptime_field_a = 6291,
            .writer = null,
        }, .{
            .comptime_field_b = Parameter(usize, "larry_bank_id", null),
            .name = Parameter([]const u8, "larry_name_id", resolveLarryName),
            .pointer = Parameter(*const usize, "larry_number", null),
        }),
        .WriterBoy = Parameterized(TestConfigStruct{
            .name = "Writer Boy",
        }, .{
            .writer = Parameter(std.io.AnyWriter, "some_writer", sideEffectyResolver),
        }),
        .Default = TestConfigStruct{
            .flags = .{
                .bit_1 = false,
                .bit_2 = true,
                .bit_3 = false,
                .rest = 2,
            },
            .comptime_field_a = 123,
            .comptime_field_b = 320432,
            .name = "Default",

            .pointer = &larrys_num,
            .writer = null,
        },
        .PartialA = TestConfigStruct{
            .flags = .{ .bit_1 = true },
            .comptime_field_a = 999,
        },
        .PartialB = Parameterized(TestConfigStruct{
            .comptime_field_b = 998,
            .pointer = &larrys_num,
            .writer = null,
        }, .{
            .name = Parameter([]const u8, "partial_name", null),
        }),
    });

    const from = Registry.BuilderMixin;
    const profile = Registry.ProfileMixin;
    const default = Registry.DefaultMixin;
};

test "config (default value)" {
    const default = TestConfigStruct.default(.{});

    try testing.expectEqual(default, TestConfigStruct{
        .flags = .{
            .bit_1 = false,
            .bit_2 = true,
            .bit_3 = false,
            .rest = 2,
        },
        .comptime_field_a = 123,
        .comptime_field_b = 320432,
        .name = "Default",

        .pointer = &TestConfigStruct.larrys_num,
        .writer = null,
    });
}

test "config (profile)" {
    const profile = TestConfigStruct.profile(.Harry, .{});

    try testing.expectEqual(profile, TestConfigStruct{
        .flags = .{
            .bit_1 = true,
            .bit_2 = false,
            .bit_3 = true,
            .rest = 10,
        },
        .comptime_field_a = 100,
        .comptime_field_b = 0,
        .name = "Harry Harryson",

        .pointer = &TestConfigStruct.larrys_num,
        .writer = null,
    });
}

test "config (parameterized profile)" {
    var string: [64]u8 = .{0} ** 64;
    var stream = std.io.fixedBufferStream(string[0..]);
    var w = stream.writer();

    const larry_num: usize = 12321;

    const val = TestConfigStruct.profile(.Larry, .{
        .larry_bank_id = 943,
        .larry_name_id = 1,
        .larry_number = &larry_num,
    });

    try testing.expectEqual(val, TestConfigStruct{
        .flags = .{},
        .comptime_field_a = 6291,
        .writer = null,
        .comptime_field_b = 943,
        .name = "Larry Jerryson",
        .pointer = &larry_num,
    });

    const writer_val = TestConfigStruct.profile(.WriterBoy, .{
        .some_writer = w.any(),
    });

    try testing.expectEqual(writer_val, TestConfigStruct{
        .name = "Writer Boy",
        .writer = w.any(),
    });

    try testing.expectEqualSlices(u8, string[0..("Evil function").len], "Evil function");
}

test "config (value composition)" {
    var val_a_b = TestConfigStruct.from(.PartialA, .{});
    const res = val_a_b.extend(.{
        .comptime_field_b = 998,
        .pointer = &TestConfigStruct.larrys_num,
        .writer = null,
        .name = "Name Here",
    }).finalize();

    const res2 = val_a_b.combine(.PartialB, .{
        .partial_name = "Name Here",
    }).finalize();

    try testing.expectEqual(res, res2);
}

test "overwritting values" {
    var partial_val_builder = TestConfigStruct.from(.PartialA, .{});

    // makes sure composition doesn't overwrite the original values with default values...
    const config = partial_val_builder.extend(.{
        .comptime_field_b = 10230,
    }).finalize();

    try testing.expect(config.comptime_field_a == 999);
}
