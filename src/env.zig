//! Note:
//! Backing in this context refers to the actual struct used to track the references
//! to environment data
//! and parent type refers to the actual object that owns the data.
const std = @import("std");
const RefConfig = struct {
    field: ?[]const u8 = null,
    mutable: bool = false,
};

fn ResolveInnerType(comptime T: type, comptime config: RefConfig) type {
    const AsPtr = if (!config.mutable) *const T else *T;

    return if (@typeInfo(T) == .pointer) T else AsPtr;
}
/// returns a const non-owning pointer to the object
/// (might enforce a bit more memory safety here later)
pub fn Ref(comptime T: type, comptime config: RefConfig) type {
    return struct {
        pub const field = config.field;
        pub const InnerType = ResolveInnerType(T, config);
        const Self = @This();

        inner: InnerType,
    };
}

const StructField = std.builtin.Type.StructField;
const EnumField = std.builtin.Type.EnumField;
const Enum = std.builtin.Type.Enum;

fn ContextEnumFromFields(comptime T: type) type {
    const info = @typeInfo(T);

    switch (info) {
        .@"struct" => |st| {
            comptime var vals: []const EnumField = &.{};

            for (st.fields, 0..) |fld, v| {
                vals = vals ++ [_]EnumField{.{
                    .name = fld.name,
                    .value = v,
                }};
            }
            return @Type(.{ .@"enum" = std.builtin.Type.Enum{
                .tag_type = u16,
                .decls = &.{},
                .is_exhaustive = true,
                .fields = vals,
            } });
        },
        else => unreachable,
    }
}

fn validateFieldAsRef(field: StructField) bool {
    const declType: type = if (@hasDecl(field.type, "InnerType"))
        field.type.InnerType
    else
        return false;

    const innerField: type = if (@hasField(field.type, "inner"))
        @FieldType(field.type, "inner")
    else
        return false;

    return innerField == declType;
}

// precheck the given type to prevent any... oopsies
fn validateType(comptime T: type) void {
    switch (@typeInfo(T)) {
        .@"struct" => |st| {
            for (st.fields) |fld| {
                if (!validateFieldAsRef(fld))
                    @compileError("Invalid env backing type, all fields must be Refs! " ++ @typeName(fld.type));
            }
        },
        else => @compileError("Invalid Env backing type: " ++ @typeName(T)),
    }
}

const BindingEntry = struct {
    ft: type,
    parent_name: []const u8,
    backing_name: []const u8,
};

fn MakeRefBindings(comptime T: type) type {
    // given this is an internal function, I don't think it matters that we check
    // for the datatype being valid here... (it is done previously)
    const info = @typeInfo(T).@"struct";

    // this will need to work with only consecutive valued enums defined by ContextEnumFromFields (or else everything will explode lmao)
    comptime var typeMap: []const BindingEntry = &.{};

    for (info.fields) |fld| {
        typeMap = typeMap ++ [1]BindingEntry{.{
            .ft = fld.type.InnerType,
            .parent_name = fld.type.field orelse fld.name,
            .backing_name = fld.name,
        }};
    }

    return struct {
        const FieldSetEnum = ContextEnumFromFields(T);
        const map = typeMap;

        pub fn typeFor(comptime val: FieldSetEnum) type {
            return typeMap[@intFromEnum(val)].ft;
        }

        pub fn fieldName(comptime val: FieldSetEnum) []const u8 {
            return typeMap[@intFromEnum(val)].backing_name;
        }
    };
}

fn FindParentFieldType(pt: type, fname: []const u8) type {
    const fields = @typeInfo(@typeInfo(pt).pointer.child);

    for (fields.@"struct".fields) |fld| {
        if (std.mem.order(u8, fname, fld.name) == .eq) return fld.type;
    }

    @compileError("Could not find matching field for name: " ++ fname ++ " (FindParentFieldInType)");
}

pub fn Empty() type {
    return struct {
    };
}

/// Ensure LHS is a pointer
pub fn populate(lhs: anytype, rhs: anytype) void {
    const lhs_info = @typeInfo(@TypeOf(lhs));
    const rhs_info = @typeInfo(@TypeOf(rhs));

    switch (lhs_info) {
        .pointer => {},
        else => 
            @compileError("lhs (" ++ @typeName(@TypeOf(lhs)) ++ ") must be a pointer"),
    }
    switch (rhs_info) {
        .@"struct" => {},
        else => 
            @compileError("rhs (" ++ @typeName(@TypeOf(rhs)) ++ ") must be a struct type"),
    }

    inline for (rhs_info.@"struct".fields) |fld| {
        if (@hasField(lhs_info.pointer.child, fld.name))
            @field(lhs, fld.name) = @field(rhs, fld.name);
    }
}

pub fn For(comptime T: type) type {
    validateType(T);

    return struct {
        pub const ContextEnum = ContextEnumFromFields(T);
        const Bindings = MakeRefBindings(T);
        const Self = @This();

        /// Defines an env subset type which can be automatically populated by a factory
        pub fn EnvSubset(comptime fields: anytype) type {
            comptime var field_infos: []const StructField = &.{};
            for (fields) |enum_lit| {
                const matching_field = std.meta.fieldInfo(T, enum_lit);
                const MatchingFieldType = matching_field.type;

                // This is janky due to how the env system mapps fields oops
                const mapped_field_info = StructField{
                    .default_value_ptr = null,
                    .type = MatchingFieldType.InnerType,
                    .is_comptime = false,
                    .alignment = @alignOf(MatchingFieldType.InnerType),
                    .name = matching_field.name,
                };
                field_infos = field_infos ++ [1]StructField{mapped_field_info};
            }

            const SubsetType = @Type(.{
                .@"struct" = .{
                    .fields = field_infos,
                    .decls = &.{},
                    .layout = .auto,
                    .is_tuple = false,
                },
            });

            return SubsetType;
        }

        inner: T,

        pub fn ResolveInner(comptime field: ContextEnum) type {
            return Bindings.typeFor(field);
        }

        pub fn get(self: *const Self, comptime field: ContextEnum) ResolveInner(field) {
            const name = comptime Bindings.fieldName(field);

            return @field(self.inner, name).inner;
        }

        /// 'name' should be the backing field's name
        /// also, we need the pointer version of the mt field
        fn findMatchingFieldInBacking(mt: type, name: []const u8) !BindingEntry {
            const PointerType = @Type(.{
                .Pointer = .{ .child = mt },
            });

            for (Bindings.map) |entry| {
                if (mt == PointerType and std.mem.order(u8, name, entry.backing_name) == .eq)
                    return entry;
            }
        }

        /// Must be initialized from a parent instance with compatible fields
        /// as defined in the initial env backing struct used when generating the environment
        ///
        /// val must also be a pointer to the instance since the environment works entirely off of pointers.
        /// It is up to the caller to ensure that environment pointers stay valid for the lifetime of the environment
        /// (Which basically means don't carelessly init the env from a local instance)
        pub fn init(val: anytype) Self {
            const ParentType = @TypeOf(val);

            // this must refer to a pointer
            comptime {
                const parent_info = @typeInfo(ParentType);

                switch (parent_info) {
                    .pointer => {},
                    else => @compileError("Env structs must be initialized from a valid pointer!"),
                }
            }

            var backing: T = undefined;

            inline for (Bindings.map) |*bind| {
                const backing_name = bind.backing_name;
                const parent_name = bind.parent_name;
                // if the field is a pointer, simply copy it over to the inner struct
                const pft = FindParentFieldType(ParentType, parent_name);
                @field(backing, backing_name).inner = switch (@typeInfo(pft)) {
                    .pointer => @field(val, parent_name),
                    else => &@field(val, parent_name),
                };
                // otherwise, make a reference to it in the parent (this is why a pointer must be passed)
            }

            return Self{
                .inner = backing,
            };
        }

        /// initialize the env fields directly from a structure
        /// This is meant to be used mainly for testing purposes where creating
        /// an entire context is unwieldy.
        pub fn initRaw(val: anytype) Self {
            var backing: T = undefined;

            inline for (Bindings.map) |bind| {
                if (@hasField(@TypeOf(val), bind.backing_name)) {
                    @field(backing, bind.backing_name).inner =
                        @field(val, bind.backing_name);
                }
            }

            return Self{
                .inner = backing,
            };
        }
    };
}
