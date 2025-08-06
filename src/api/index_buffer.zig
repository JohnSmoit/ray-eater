const vk = @import("vulkan");
const buf_api = @import("buffer.zig");

const GenericBuffer = buf_api.GenericBuffer;
const CommandBuffer = @import("command_buffer.zig");
const DeviceHandler = @import("base.zig").DeviceHandler;
const Context = @import("../context.zig");
const AnyBuffer = buf_api.AnyBuffer;

fn getIndexType(T: type) vk.IndexType {
    return switch (T) {
        u8 => .uint8,
        u16 => .uint16,
        u32 => .uint32,
        else => @compileError("Invalid index format (TODO: Better deduction)"),
    };
}

pub fn IndexBuffer(T: type) type {
    return struct {
        const Self = @This();
        const index_type = getIndexType(T);

        const Inner = GenericBuffer(T, .{ .memory = .{
            .device_local_bit = true,
        }, .usage = .{
            .index_buffer_bit = true,
            .transfer_dst_bit = true,
        } });

        buf: Inner,

        pub fn create(ctx: *const Context, size: usize) !Self {
            const buff = try Inner.create(ctx, size);

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

        pub fn deinit(self: *Self) void {
            self.buf.deinit();
        }

        pub fn bind(self: *Self, cmd_buf: *const CommandBuffer) void {
            self.buf.dev.pr_dev.cmdBindIndexBuffer(cmd_buf.h_cmd_buffer, self.buf.h_buf, 0, index_type);
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
    };
}
