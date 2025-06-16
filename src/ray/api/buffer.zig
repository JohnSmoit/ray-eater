const vk = @import("vulkan");

const std = @import("std");
const api = @import("vulkan.zig");

const log = std.log.scoped(.buffer);
const meth = @import("../math.zig");
const util = @import("../util.zig");

const TypeInfo = std.builtin.Type;
const StructInfo = std.builtin.Type.Struct;

fn validateType(T: type) StructInfo {
    const info = @typeInfo(T);

    return switch (info) {
        .@"struct" => |s| if (s.layout == .@"extern") s else @compileError(
            "Binding descriptor types must have a known layout and field composition",
        ),
        else => @compileError("Fuck you! extern structs only!"),
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
        else => @compileError("Unsupported input type"),
    };
}

fn getVertexAttributeDescriptions(T: type) []const vk.VertexInputAttributeDescription {
    const s = validateType(T);
    comptime var descriptions: []const vk.VertexInputAttributeDescription = &.{};

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
}

pub fn VertexInputDescription(T: type) type {
    return struct {
        pub const vertex_desc: vk.VertexInputBindingDescription = getBindingDescription(T);
        pub const attrib_desc: []const vk.VertexInputAttributeDescription = getVertexAttributeDescriptions(T);
    };
}

pub fn GenericBuffer(T: type, comptime usage: vk.BufferUsageFlags) type {
    return struct {
        const Self = @This();

        pub const element_size: usize = @sizeOf(T);
        pub const Description = VertexInputDescription(T);

        h_buf: vk.Buffer = .null_handle,
        h_mem: ?vk.DeviceMemory = null,
        size: usize = 0,
        dev: *const api.Device = undefined,

        /// NOTE: This function allocates memory, but since the memory used for buffers
        /// is not neccesarily normal heap memory, I need to do some reasearch how/whether
        /// standard libraries can work with GPU memory types
        ///
        /// For now, I just do the memory compatibility checks here every time set is called
        /// so beware!
        pub fn create(dev: *const api.Device, size: usize) !Self {
            var buf = Self{
                .h_buf = try dev.pr_dev.createBuffer(&.{
                    .size = size * element_size,
                    .usage = usage,
                    .sharing_mode = .exclusive,
                }, null),
                .size = size,
                .dev = dev,
            };
            errdefer dev.pr_dev.destroyBuffer(buf.h_buf, null);

            buf.h_mem = try Self.allocateMemory(dev, buf.h_buf);
            log.debug("Successfully allocated vertex buffer memory!", .{});

            return buf;
        }

        pub fn bytesSize(self: *const Self) usize {
            return element_size * self.size;
        }

        fn allocateMemory(dev: *const api.Device, h_buf: vk.Buffer) !vk.DeviceMemory {
            const pr_dev = &dev.pr_dev;

            const mem_reqs = pr_dev.getBufferMemoryRequirements(h_buf);
            const dev_mem_props = dev.getMemProperties();

            const requested_flags = vk.MemoryPropertyFlags{
                .host_coherent_bit = true,
                .host_visible_bit = true,
            };

            var found = false;
            var chosen_mem: u32 = 0;

            for (0..dev_mem_props.memory_type_count) |i| {
                const mem_flags = dev_mem_props.memory_types[i].property_flags;
                if (mem_reqs.memory_type_bits & (@as(u32, 1) << @intCast(i)) != 0 and mem_flags.contains(requested_flags)) {
                    found = true;
                    chosen_mem = @intCast(i);
                    break;
                }
            }

            if (!found) return error.IncompatibleMemory;

            const h_mem = try pr_dev.allocateMemory(&.{
                .allocation_size = mem_reqs.size,
                .memory_type_index = chosen_mem,
            }, null);
            errdefer pr_dev.freeMemory(h_mem, null);

            try pr_dev.bindBufferMemory(h_buf, h_mem, 0);

            return h_mem;
        }

        pub fn setData(self: *Self, elem: []const T) !void {
            const bytes_size = self.bytesSize();
            const mem = try self.dev.pr_dev.mapMemory(
                self.h_mem.?,
                0,
                bytes_size,
                .{},
            );

            @memcpy(
                @as([*]u8, @ptrCast(mem))[0..bytes_size],
                        // Bad const cast, but as the source bytes, these should be unmodifiable no?
                @as([*]u8, @constCast(@ptrCast(elem)))[0..bytes_size],
            );

            self.dev.pr_dev.unmapMemory(self.h_mem.?);
        }

        pub fn deinit(self: *const Self) void {
            self.dev.pr_dev.destroyBuffer(self.h_buf, null);

            if (self.h_mem != null) {
                self.dev.pr_dev.freeMemory(self.h_mem.?, null);
            }
        }

        pub fn bind(self: *const Self, cmd_buf: *const api.CommandBufferSet) void {
            self.dev.pr_dev.cmdBindVertexBuffers(
                cmd_buf.h_cmd_buffer,
                0,
                1,
                util.asManyPtr(vk.Buffer, &self.h_buf),
                &[_]vk.DeviceSize{0},
            );
        }
    };
}
