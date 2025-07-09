const std = @import("std");
const RefConfig = struct {
    field: ?[]const u8 = null,
};
/// returns a const non-owning pointer to the object 
/// (might enforce a bit more memory safety here later)
pub fn Ref(comptime T: type, comptime config: RefConfig) type {
    return struct {
        pub const field = config.field;
        pub const InnerType = T;
        const Self = @This();
        
        inner: *const InnerType,
    };
}

const EnumField = std.builtin.Type.EnumField;
const Enum = std.builtin.Type.Enum;

fn ContextEnumFromFields(comptime T: type) type {
    const info = @typeInfo(T);

    switch (info) {
        .@"struct" => |st| {
            comptime var vals: []const EnumField = &.{};

            @compileLog("Fuck: ", T.InnerType);

            for (st.fields, 0..) |fld, v| {
                vals = vals ++ [_]EnumField{.{
                    .name = fld.name,
                    .value = v,
                }};
            }
            return @Type(.{
                .@"enum" = std.builtin.Type.Enum{
                    .tag_type = u16,
                    .decls = &.{},
                    .is_exhaustive = true,
                    .fields = vals,
                }
            });
        },
        else => unreachable,
    }

}

fn validateType(comptime T: type) void {
    switch (@typeInfo(T)) {
        .@"struct" => {},
        else => @compileError("Invalid Env backing type: " ++ @typeName(T)),
    }
}


fn MakeRefBindings(comptime T: type) type {
    // given this is an internal function, I don't think it matters that we check
    // for the datatype being valid here... (it is done previously)
    const info = @typeInfo(T).@"struct";

    // this will need to work with only consecutive valued enums defined by ContextEnumFromFields (or else everything will explode lmao)
    comptime var typeMap: []const type = &.{};

    for (info.fields) |fld| {
        typeMap = typeMap ++ [1]type{fld.type};
    }

    return struct {
        const FieldSetEnum = ContextEnumFromFields(T);

        pub fn typeFor(comptime val: FieldSetEnum) type {
            return typeMap[@intFromEnum(val)];
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
            _ = self;
            return undefined;
        }

        pub fn init(val: anytype) Self {

            _ = val;
            return undefined;
        }
        
        // fields must be a compile-time known tuple of whatever ContextEnum (backing struct fields enum)
        // values are.
        // self.env.get(.di).something...;
        //
        // Actually, not sure this really helps, 
        // so imma omit it for now..
        // pub fn Scope(comptime fields: anytype) type {
        //     _ = fields;
        // }
    };
}
