//! Type for uniform buffers

const buffer = @import("buffer.zig");
const api = @import("vulkan.zig");

const AnyBuffer = buffer.AnyBuffer;
const GenericBuffer = buffer.GenericBuffer;

pub fn UniformBuffer(T: type) type {
    return struct {
        const Self = @This();
        const InnerBuffer = GenericBuffer(T, .{ .memory = .{
            .device_local_bit = true,
        }, .usage = .{
            .transfer_dst_bit = true,
            .uniform_buffer_bit = true,
        } });

        buf: InnerBuffer,
        mem: []T,

        pub fn create(dev: *const api.Device, size: usize) !Self {
            const buf = try InnerBuffer.create(dev, size);
            errdefer buf.deinit(); // conditionally deinits allocated memory if it exists

            const mem = try buf.mapMemory();
            errdefer buf.unmapMemory();

            return Self{ .mem = mem, .buf = buf };
        }

        pub fn bind(ctx: *anyopaque, cmd_buf: *const api.CommandBufferSet) !void {
            // No-Op

            _ =  ctx;
            _ = cmd_buf;
        }

        pub fn buffer(self: *Self) AnyBuffer {
            return AnyBuffer{
                .cfg = &InnerBuffer.cfg,
                .handle = self.buf.h_buf,
                .ptr = self,
                .size = self.buf.bytesSize(),
                .vtable = &.{
                    .bind = bind,
                    .setData = setData,
                    .deinit = deinit,
                },
            };
        }

        pub fn setData(ctx: *anyopaque, data: *const anyopaque) !void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            const elem: []const T = @as([*]const T, @ptrCast(@alignCast(data)))[0..self.buf.size];

            @memcpy(self.mem, elem);
        }

        pub fn deinit(ctx: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(ctx));

            self.buf.unmapMemory();
            self.buf.deinit();
        }
    };
}


