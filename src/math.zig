const std = @import("std");
const math = std.math;

//TODO: Generalize these with some metaprogramming
//to make it more viable to have a more expansive set of
//vector types
pub const Vec3 = extern struct {
    pub const global_up: Vec3 = vec(.{ 0.0, -1.0, 0.0 });
    pub const len: usize = 3;

    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,

    pub fn vals(self: Vec3) struct { f32, f32, f32 } {
        return .{ self.x, self.y, self.z };
    }

    pub fn negate(self: Vec3) Vec3 {
        return vec(.{ -self.x, -self.y, -self.z });
    }

    pub fn at(self: *Vec3, index: usize) *f32 {
        // wrapping behaviour because I can't be assed to make it optional or an error
        const ind = @mod(index, len);
        return switch (ind) {
            0 => &self.x,
            1 => &self.y,
            2 => &self.z,
            else => unreachable,
        };
    }

    pub fn mul(self: Vec3, mat: Mat4) Vec3 {
        var res = Vec3{};
        const src = self.vals();

        for (0..(mat.data.len - 1)) |col| {
            for (col) |val| {
                res.at(col).* += src[col] * val;
            }
        }

        return res;
    }
};

pub const Vec4 = extern struct {
    pub const len: usize = 4;

    x: f32,
    y: f32,
    z: f32,
    w: f32,

    pub fn vals(self: Vec4) struct { f32, f32, f32, f32 } {
        return .{ self.x, self.y, self.z, self.w };
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
        4 => Vec4,
        else => @compileError("No corresponding vector type"),
    };
}

/// Creates an N-dimensional vector based on the number and types of arguments
/// specified in the args tuple
pub fn vec(args: anytype) resolveVec(args.len) {
    return switch (args.len) {
        2 => Vec2{ .x = args[0], .y = args[1] },
        3 => Vec3{ .x = args[0], .y = args[1], .z = args[2] },
        4 => Vec4{ .x = args[0], .y = args[1], .z = args[2], .w = args[3] },
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

//NOTE: Temporary usage of ZLM cuz I can't seem to get my linear algebra correct
/// ## Brief
/// A 4-by-4 matrix used extensively in transformation and rendering operations
///
/// ## Usage
/// The actual elements of the matrix are laid out in column major order,
/// that means that contiguous matrix elements represent elements of a single column in memory.
/// This means that all member functions and direct manipulations of the matrix's data
/// MUST operate on the matrix in column major ORDER OR ELSE BAD THINGS WILL HAPPEN
/// I AM IN YOUR WALLS
pub const Mat4 = extern struct {
    // NOTE: Actually I think Imma just maintain the column major invariant
    // myself in the implementation rather than make that the user's problem
    pub const rank: usize = 2;
    pub const rows: usize = 4;
    pub const cols: usize = 4;

    data: [cols][rows]f32 = undefined,

    // NOTE: I automatically transpose the matrix to be row-major in the formatter
    // cuz I think that's visually more intuitive for poeple, if this causes confusion,
    // oops.
    // ALL user-supplied data will be auto transposed so they can still do row-major ordering
    pub fn format(
        self: Mat4,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        const mat = self.transpose();
        try writer.writeAll("=====MATRIX4x4=====\n");
        for (mat.data) |col| {
            try writer.print("[{d:2.3}, {d:2.3}, {d:2.3}, {d:2.3}]\n", .{ col[0], col[1], col[2], col[3] });
        }

        try writer.writeAll("=====ENDMATRIX4x4======\n");

        _ = fmt;
        _ = options;
    }

    pub fn create(vals: anytype) Mat4 {
        var mat = of(0.0);

        inline for (vals, 0..) |col, y| {
            inline for (col, 0..) |num, x| {
                const v = @as(f32, num);
                mat.data[x][y] = v;
            }
        }

        return mat;
    }

    pub fn createCM(vals: anytype) Mat4 {
        return create(vals).transpose();
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

    pub fn rotateX(mat: Mat4, rads: f32) Mat4 {
        const rotation = create(.{
            .{ 1.0, 0.0, 0.0, 0.0 },
            .{ 0.0, @cos(rads), @sin(rads), 0.0 },
            .{ 0.0, -@sin(rads), @cos(rads), 0.0 },
            .{ 0.0, 0.0, 0.0, 1.0 },
        });

        return mul(mat, rotation);
    }

    pub fn rotateY(mat: Mat4, rads: f32) Mat4 {
        return mat.mul(create(.{
            .{ @cos(rads), 0, @sin(rads), 0 },
            .{ 0, 1, 0, 0 },
            .{ -@sin(rads), 0, @cos(rads), 0 },
            .{ 0, 0, 0, 1 },
        }));
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
                res.data[y][x] = vals[x - sx][y - sy];
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
        const z = norm(sub(center, eye)); // forward (camera looks down -Z)
        const x = norm(cross(z, world_up)); // right
        const y = norm(cross(x, z)); // up

        var view = identity();
        // rotation part
        view = view.setRegion(0, 3, 0, 3, .{
            x.vals(),
            y.vals(),
            z.negate().vals(),
        });

        // translation part
        const tx = -dot(x, eye);
        const ty = -dot(y, eye);
        const tz = -dot(z, eye);

        return view.translate(vec(.{ tx, ty, tz }));
    }

    pub fn perspective(fov: f32, aspect: f32, near: f32, far: f32) Mat4 {
        const vp: f32 = 1.0 / @tan(fov / 2.0);
        const as: f32 = vp / aspect;

        return create(.{
            .{ as, 0, 0, 0 },
            .{ 0, -vp, 0, 0 },
            .{ 0, 0, far / (far - near), -(near * far) / (far - near) },
            .{ 0, 0, 1.0, 0 },
        });
    }

    pub fn transpose(mat: Mat4) Mat4 {
        var res = Mat4{};

        for (0..cols) |x| {
            for (0..rows) |y| {
                res.data[y][x] = mat.data[x][y];
            }
        }

        return res;
    }

    pub fn mul(a: Mat4, b: Mat4) Mat4 {
        var res = of(0);

        for (0..cols) |col| {
            for (0..rows) |row| {
                var sum: f32 = 0.0;

                for (0..cols) |i| {
                    const v1 = a.data[i][row];
                    const v2 = b.data[col][i];

                    sum += v1 * v2;
                }

                res.data[col][row] = sum;
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
