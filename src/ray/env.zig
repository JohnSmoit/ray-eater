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

fn MakeRefBindings(comptime T: type) type {
    // given this is an internal function, I don't think it matters that we check
    // for the datatype being valid here... (it is done previously)
    const info = @typeInfo(T).@"struct";

    // this will need to work with only consecutive valued enums defined by ContextEnumFromFields (or else everything will explode lmao)
    comptime var typeMap: []const struct { type, []const u8 } = &.{};

    for (info.fields) |fld| {
        typeMap = typeMap ++ [1]type{ fld.type, fld.type.field orelse fld.name };
    }

    return struct {
        const FieldSetEnum = ContextEnumFromFields(T);
        const map = typeMap;

        pub fn typeFor(comptime val: FieldSetEnum) type {
            return typeMap[@intFromEnum(val)][0];
        }

        pub fn fieldName(comptime val: FieldSetEnum) []const u8 {
            return typeMap[@intFromEnum(val)][1];
        }
    };
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
            const name = Bindings.fieldName(field);

            return @field(self.inner, name).inner;
        }
        
        /// Must be initialized from a parent instance with compatible fields
        /// as defined in the initial env backing struct used when generating the environment
        ///
        /// val must also be a pointer to the instance since the environment works entirely off of pointers.
        /// It is up to the caller to ensure that environment pointers stay valid for the lifetime of the environment
        /// (Which basically means don't carelessly init the env from a local instance)
        pub fn init(val: anytype) Self {
            const ParentType = @TypeOf(val);
            const parent_info = @typeInfo(ParentType).@"struct";

            inline for (parent_info.fields) |fld| {
                const field_type_info = @typeInfo(fld.type);
            }
        }
    };
}
