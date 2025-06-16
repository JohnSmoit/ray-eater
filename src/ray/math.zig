//TODO: Generalize these with some metaprogramming
//to make it more viable to have a more expansive set of
//vector types
pub const Vec3 = extern struct {
    x: f32,
    y: f32,
    z: f32,
};

pub const Vec2 = extern struct {
    x: f32,
    y: f32,
};

fn resolveVec(comptime args: anytype) type {
    return switch (args.len) {
        2 => Vec2,
        3 => Vec3,
        else => @compileError("No corresponding vector type"),
    };
}

/// Creates an N-dimensional vector based on the number and types of arguments
/// specified in the args tuple
pub fn nVec(comptime args: anytype) resolveVec(args) {
    return switch (args.len) {
        2 => Vec2{ .x = args[0], .y = args[1] },
        3 => Vec3{ .x = args[0], .y = args[1], .z = args[2] },
        else => unreachable,
    };
}
