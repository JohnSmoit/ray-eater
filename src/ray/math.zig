const std = @import("std");
const math = std.math;

//TODO: Generalize these with some metaprogramming
//to make it more viable to have a more expansive set of
//vector types
pub const Vec3 = extern struct {
    pub const global_up: Vec3 = vec(.{ 0.0, 1.0, 0.0 });
    pub const len: usize = 3;

    x: f32,
    y: f32,
    z: f32,

    pub fn vals(self: Vec3) struct { f32, f32, f32 } {
        return .{ self.x, self.y, self.z };
    }
};

pub const Vec2 = extern struct {
    pub const len: usize = 2;

    x: f32,
    y: f32,

    pub fn vals(self: Vec2) struct { f32, f32 } {
        return .{ self.x, self.y };
    }
};

fn resolveVec(args: comptime_int) type {
    return switch (args) {
        2 => Vec2,
        3 => Vec3,
        else => @compileError("No corresponding vector type"),
    };
}

/// Creates an N-dimensional vector based on the number and types of arguments
/// specified in the args tuple
pub fn vec(args: anytype) resolveVec(args.len) {
    return switch (args.len) {
        2 => Vec2{ .x = args[0], .y = args[1] },
        3 => Vec3{ .x = args[0], .y = args[1], .z = args[2] },
        else => unreachable,
    };
}

pub fn norm(v: Vec3) Vec3 {
    return sdiv(v, mag(v));
}

pub fn mag(v: Vec3) f32 {
    return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
}

pub fn cross(a: Vec3, b: Vec3) Vec3 {
    return vec(.{
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x,
    });
}

pub fn dot(a: Vec3, b: Vec3) f32 {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

pub fn smult(v: Vec3, s: f32) Vec3 {
    var res = v;
    res.x *= s;
    res.y *= s;
    res.z *= s;

    return res;
}

pub fn sdiv(v: Vec3, s: f32) Vec3 {
    var res = v;
    res.x /= s;
    res.y /= s;
    res.z /= s;

    return res;
}

pub fn sub(a: Vec3, b: Vec3) Vec3 {
    return vec(.{ a.x - b.x, a.y - b.y, a.z - b.z });
}

pub fn radians(f: f32) f32 {
    return f * (math.pi / 180.0);
}

pub const Mat4 = extern struct {
    pub const rank: usize = 2;
    pub const rows: usize = 4;
    pub const cols: usize = 4;

    data: [cols][rows]f32 = undefined,

    pub fn format(
        self: Mat4,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.writeAll("=====MATRIX4x4=====\n");
        for (self.data) |row| {
            try writer.print("[{d:2.3}, {d:2.3}, {d:2.3}, {d:2.3}]\n", .{row[0], row[1], row[2], row[3]});
        }

        try writer.writeAll("=====ENDMATRIX4x4======\n");

        _ = fmt;
        _ = options;
    }

    pub fn create(vals: anytype) Mat4 {
        var mat = of(0.0);

        inline for (vals, 0..) |row, x| {
            inline for (row, 0..) |num, y| {
                const v = @as(f32, num);
                mat.data[x][y] = v;
            }
        }

        return mat;
    }

    pub fn identity() Mat4 {
        return create(.{
            .{ 1.0, 0.0, 0.0, 0.0 },
            .{ 0.0, 1.0, 0.0, 0.0 },
            .{ 0.0, 0.0, 1.0, 0.0 },
            .{ 0.0, 0.0, 0.0, 1.0 },
        });
    }

    pub fn of(val: f32) Mat4 {
        var mat = Mat4{};

        comptime var x: usize = 0;
        comptime var y: usize = 0;

        inline while (y < cols) : (y += 1) {
            inline while (x < rows) : (x += 1) {
                mat.data[x][y] = val;
            }

            x = 0;
        }

        return mat;
    }

    pub fn rotateZ(mat: Mat4, rads: f32) Mat4 {
        const rotation = create(.{
            .{ math.cos(rads), -math.sin(rads), 0.0, 0.0 },
            .{ math.sin(rads), math.cos(rads), 0.0, 0.0 },
            .{ 0.0, 0.0, 1.0, 0.0 },
            .{ 0.0, 0.0, 0.0, 1.0 },
        });

        return mul(mat, rotation);
    }

    pub fn setRegion(
        mat: Mat4,
        /// Starting X -- inclusive
        sx: comptime_int,
        /// Ending X -- exclusive
        ex: comptime_int,
        /// Starting Y -- inclusive
        sy: comptime_int,
        /// Ending Y -- exclusive
        ey: comptime_int,
        /// tuple of values
        vals: anytype,
    ) Mat4 {
        var res = mat;
        // comptime {
        //     if (vals.len != @as(usize, ey - sy) or vals[0].len != @as(usize, ex - sx))
        //         @compileError("Invalid initializer bounds (must match parameters)");
        //         @compileLog(ey - sy, vals.len, ex - sx, vals[0].len);
        // }

        comptime var x: usize = sx;
        comptime var y: usize = sy;

        inline while (x < ex) : (x += 1) {
            inline while (y < ey) : (y += 1) {
                res.data[x][y] = vals[x - sx][y - sy];
            }

            y = sy;
        }

        return res;
    }

    pub fn translate(mat: Mat4, by: Vec3) Mat4 {
        return mat.setRegion(0, 3, 3, 4, .{
            .{mat.data[0][3] + by.x},
            .{mat.data[1][3] + by.y},
            .{mat.data[2][3] + by.z},
        });
    }

    pub fn lookAt(eye: Vec3, center: Vec3, world_up: Vec3) Mat4 {
        // compute coordinate frame
        const forward = norm(sub(eye, center));
        const up = norm(cross(forward, world_up));
        const right = norm(cross(forward, up));

        return translate(of(0.0), vec(.{
            dot(eye, right),
            dot(eye, up),
            dot(eye, forward),
        })).setRegion(0, 3, 0, 3, .{
            up.vals(),
            forward.vals(),
            right.vals(),
        });
    }

    pub fn perspective(fov: f32, aspect: f32, near: f32, far: f32) Mat4 {
        const angle: f32 = fov / 2.0;

        const right: f32 = math.cos(angle);
        const left: f32 = -right;
        const top: f32 = right * aspect;
        const bottom: f32 = -right * aspect;

        const width: f32 = right - left;
        const height: f32 = top - bottom;

        return create(.{
            .{ (2.0 * near) / width, 0, (right + left) / (width), 0 },
            .{ 0, (2.0 * near) / height, (top + bottom) / height, 0 },
            .{ 0, 0, (-(far + near)) / (far - near), (-2 * far * near) / (far - near) },
            .{ 0, 0, -1.0, 0 },
        });
    }

    pub fn mul(a: Mat4, b: Mat4) Mat4 {
        var res = of(0);
        for (0..cols) |x| {
            for (0..rows) |y| {
                var sum: f32 = 0.0;


                for (0..cols) |c| {
                    const v1 = a.data[x][c];
                    const v2 = b.data[c][y];

                    sum += v1 * v2;
                }

                res.data[x][y] = sum;
            }
        }

        return res;
    }

    pub fn eql(a: Mat4, b: Mat4) bool {
        for (0..rows) |y| {
            for (0..cols) |x| {
                if (a.data[x][y] != b.data[x][y]) {
                    return false;
                }
            }
        }

        return true;
    }
};
