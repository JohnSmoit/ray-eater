const std = @import("std");
const TypeInfo = std.builtin.Type;
const StructInfo = TypeInfo.Struct;

const vk = @import("vulkan");

const meth = @import("../math.zig");
const util = @import("../util.zig");
const buf_api = @import("buffer.zig");

const Layout = union(enum) {
    Struct: StructInfo,
    Int: TypeInfo.Int,
};

const DeviceHandler = @import("base.zig").DeviceHandler;
const CommandBuffer = @import("command_buffer.zig");
const Context = @import("../context.zig");
const AnyBuffer = buf_api.AnyBuffer;

fn validateType(comptime T: type) Layout {
    const info = @typeInfo(T);

    return switch (info) {
        .@"struct" => |s| if (s.layout == .@"extern") .{ .Struct = s } else @compileError(
            "Binding descriptor types must have a known layout and field composition",
        ),
        .int => |i| .{ .Int = i },
        else => @compileError("Fuck you! extern structs or ints only!"),
    };
}

fn getBindingDescription(T: type) vk.VertexInputBindingDescription {
    _ = validateType(T);

    const desc = vk.VertexInputBindingDescription{
        .binding = 0,
        .input_rate = .vertex,
        .stride = @sizeOf(T),
    };

    return desc;
}

// TODO: Smarter deduction for formats
fn getCorrespondingFormat(T: type) vk.Format {
    return switch (T) {
        meth.Vec3 => vk.Format.r32g32b32_sfloat,
        meth.Vec2 => vk.Format.r32g32_sfloat,
        u16 => vk.Format.r16_uint,
        u32 => vk.Format.r32_uint,
        else => @compileError("Unsupported input type"),
    };
}

fn getVertexAttributeDescriptions(T: type) []const vk.VertexInputAttributeDescription {
    const layout = validateType(T);
    comptime var descriptions: []const vk.VertexInputAttributeDescription = &.{};

    switch (layout) {
        .Struct => |s| {
            inline for (s.fields, 0..) |*field, index| {
                descriptions = descriptions ++ [_]vk.VertexInputAttributeDescription{
                    vk.VertexInputAttributeDescription{
                        .binding = 0,
                        .location = @intCast(index),
                        .offset = @offsetOf(T, field.name),
                        .format = getCorrespondingFormat(field.type),
                    },
                };
            }
            return descriptions;
        },
        .Int => return util.emptySlice(vk.VertexInputAttributeDescription),
    }
}

pub fn VertexInputDescription(T: type) type {
    return struct {
        pub const vertex_desc: vk.VertexInputBindingDescription = getBindingDescription(T);
        pub const attrib_desc: []const vk.VertexInputAttributeDescription = getVertexAttributeDescriptions(T);
    };
}

pub fn VertexBuffer(T: type) type {
    return struct {
        const Self = @This();
        const Inner = buf_api.GenericBuffer(T, .{
            .memory = .{ .device_local_bit = true },
            .usage = .{
                .transfer_dst_bit = true,
                .vertex_buffer_bit = true,
            },
        });

        pub const Description = VertexInputDescription(T);

        buf: Inner,

        pub fn create(dev: *const Context, size: usize) !Self {
            const buff = try Inner.create(dev, size);

            return .{
                .buf = buff,
            };
        }

        pub fn setData(self: *Self, data: *const anyopaque) !void {
            const elem: []const T = @as([*]const T, @ptrCast(@alignCast(data)))[0..self.buf.size];

            var staging = try self.buf.createStaging();
            defer staging.deinit();

            const staging_mem = try staging.mapMemory();
            defer staging.unmapMemory();

            @memcpy(staging_mem, elem);

            try buf_api.copy(staging.buffer(), self.buffer(), self.buf.dev);
        }

        pub fn bind(self: *Self, cmd_buf: *const CommandBuffer) void {
            self.buf.dev.pr_dev.cmdBindVertexBuffers(
                cmd_buf.h_cmd_buffer,
                0,
                1,
                util.asManyPtr(vk.Buffer, &self.buf.h_buf),
                &[_]vk.DeviceSize{0},
            );
        }

        pub fn buffer(self: *Self) AnyBuffer {
            return AnyBuffer{
                .cfg = &Inner.cfg,
                .handle = self.buf.h_buf,
                .ptr = self,
                .size = self.buf.bytesSize(),
                .vtable = buf_api.AutoVTable(Self),
            };
        }

        pub fn deinit(self: *Self) void {
            self.buf.deinit();
        }
    };
}
