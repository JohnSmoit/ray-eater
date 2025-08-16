//! WARN: Hopelessly out of date with current 
const meth = @import("ray").meth;

const std = @import("std");

const Mat4 = meth.Mat4;
const vec = meth.vec;

const expect = std.testing.expect;
// NOTE: I'm adding unit tests for the math library straight up
// because just debugging these by running the application would fucking
// suck...
const test_log = std.log.scoped(.math_tests);

fn assertEqual(matrices: anytype, op: []const u8) !void {
    const first = matrices[0];
    inline for (matrices) |v| {
        if (!Mat4.eql(first, v)) {
            test_log.err(
                "Matrix {s} failed: \nExpected: \n{s} \nGot: \n{s}",
                .{ op, first, v },
            );

            return error.MatricesNotEqualWTFBro;
        }
    }
}

const glm = @cImport({
    @cInclude("cglm/struct.h");
});

test "matrix multiplication" {
    const mat1 = Mat4.create(.{
        .{ 1.0, 2.0, 3.0, 4.0 },
        .{ 3.0, 2.0, 1.0, 1.0 },
        .{ 1.0, 2.0, 3.0, 2.0 },
        .{ 2.0, 3.0, 7.0, 3.0 },
    });

    const mat2 = Mat4.create(.{
        .{ 4.0, 5.0, 6.0, 7.0 },
        .{ 6.0, 5.0, 4.0, 3.0 },
        .{ 4.0, 6.0, 5.0, 9.0 },
        .{ 2.0, 8.0, 5.0, 3.0 },
    });

    const res = Mat4.mul(mat1, mat2);

    const correct = Mat4.create(.{
        .{ 36.0, 65.0, 49.0, 52.0 },
        .{ 30.0, 39.0, 36.0, 39.0 },
        .{ 32.0, 49.0, 39.0, 46.0 },
        .{ 60.0, 91.0, 74.0, 95.0 },
    });

    try assertEqual(.{ correct, res }, "multiplication");
}

test "matrix ordering" {
    // make sure the bloody matrices are column-major ordered
    const mat1 = Mat4.create(.{
        .{1.0, 2.0, 3.0, 4.0},
        .{1.0, 2.0, 3.0, 4.0},
        .{1.0, 2.0, 3.0, 4.0},
        .{1.0, 2.0, 3.0, 4.0},
    });

    for (mat1.data, 0..) |col, v| {
        for (col) |item| {
            const fv: f32 = @floatFromInt(v + 1);
            if (item != fv) {
                test_log.err("Matrix ordering incorrect! {d} != {d}", .{item, fv});
                test_log.err("Matrix: \n{s}", .{mat1});
                return error.NotColumnMajorBro;
            }
        }
    }
}

test "matrix translation" {
    const mat1 = Mat4.identity().translate(vec(.{ 10.0, 20.0, 30.0 }));
    const res = Mat4.create(.{
        .{ 1.0, 0.0, 0.0, 10.0 },
        .{ 0.0, 1.0, 0.0, 20.0 },
        .{ 0.0, 0.0, 1.0, 30.0 },
        .{ 0.0, 0.0, 0.0, 1.0 },
    });

    try assertEqual(.{ res, mat1 }, "translation");
}

test "matrix rotation" {
    const rot = meth.radians(45.0);
    const mat1 = Mat4.identity().rotateZ(rot);
    var res = Mat4.identity();

    const mat = glm.glms_rotate_z(glm.glms_mat4_identity(), rot);
    res.data = mat.raw;

    try assertEqual(.{ res, mat1 }, "Z rotation");
}

test "matrix projection" {
    const mat1 = Mat4.perspective(meth.radians(75.0), 600.0 / 900.0, 0.1, 30.0);
    const res = Mat4.create(.{
        .{ 1.9548, 0.0000, 0.0000, 0.0000 },
        .{ 0.0000, 1.3032, 0.0000, 0.0000 },
        .{ 0.0000, 0.0000, -1.0033, -1.0000 },
        .{ 0.0000, 0.0000, -0.1003, 0.0000 },
    }).transpose();

    try assertEqual(.{ res, mat1 }, "perspective projection");
}

test "matrix view" {
    const mat1 = Mat4.lookAt(vec(.{ 2.0, 2.0, 2.0 }), vec(.{ 0, 0, 0 }), meth.Vec3.global_up);
    const res = Mat4.create(.{
        .{ 0.7071, -0.4082, -0.5774, 0.0000 },
        .{ -0.7071, -0.4082, -0.5774, 0.0000 },
        .{ 0.0000, 0.8165, -0.5774, 0.0000 },
        .{ -0.0000, -0.0000, -3.4641, 1.0000 },
    }).transpose();

    try assertEqual(.{ res, mat1 }, "look at");
}
