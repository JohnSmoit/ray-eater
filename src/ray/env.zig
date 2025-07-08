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

fn MakeRefBindings(comptime T: type) type {
    
    return struct {
        const FieldSetEnum = ContextEnumFromFields(T);

        pub fn typeFor(comptime val: FieldSetEnum) type {

        }
    };
}

pub fn For(comptime T: type) type {

    return struct {
        pub const ContextEnum = ContextEnumFromFields(T);
        const Bindings = MakeRefBindings(T);

        pub fn ResolveInner(comptime field: ContextEnum) type {
            return Bindings.typeFor(field);
        }

        pub fn get(comptime field: ContextEnum) ResolveInner(field) {
            return undefined;
        }

        pub fn subset(comptime fields: anytype) type {
            _ = fields;
        }
    };
}
