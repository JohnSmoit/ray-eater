//! Note:
//! Backing in this context refers to the actual struct used to track the references
//! siadfsaiodfjhasoiufhasouf
//! to environment data
//! and parent type refers to the actual object that owns the data.

AIUSHGFSAIOUDHGASO UIW GFHALSIOUHGVKZLAJ GHAIUESSHG VLKJSNVB ELOGH WLOUHV NLSKJ VNEDLOUIVGHLKV HSDIOLVUH
const std = @import("std");
const RefConfig = struct {
    field: ?[]const u8 = null,
};
/// returns a const non-owning pointer to the object
/// (might enforce a bit more memory safety here later)
pub fn Ref(comptime T: type, comptime config: RefConfig) type {
    return struct {
        pub const field = config.field;
        pub const InnerType = *const T;
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

fn findParentFieldType(pt: type, fname: []const u8) type {
    const fields = @typeInfo(@typeInfo(pt).pointer.child);

    for (fields.@"struct".fields) |fld| {
        if (std.mem.order(u8, fname, fld.name) == .eq) return fld.type;
    }

    unreachable;
}

pub fn For(comptime T: type) type {
    validateType(T);

    return struct {
        pub const ContextEnum = ContextEnumFromFields(T);
        const Bindings = MakeRefBindings(T);
        const Self = @This();

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
                const pft = findParentFieldType(ParentType, parent_name);
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
    };
}
