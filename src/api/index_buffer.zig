const vk = @import("vulkan");
const buf = @import("buffer.zig");

const GenericBuffer = buf.GenericBuffer;
const CommandBuffer = @import("command_buffer.zig");
const DeviceHandler = @import("base.zig").DeviceHandler;
const Context = @import("../context.zig");
const AnyBuffer = buf.AnyBuffer;

fn getIndexType(T: type) vk.IndexType {
    return switch (T) {
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

        pub fn setData(ctx: *anyopaque, data: *const anyopaque) !void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            const elem: []const T = @as([*]const T, @ptrCast(@alignCast(data)))[0..self.buf.size];

            var staging = try self.buf.createStaging();
            defer staging.deinit();

            const staging_mem = try staging.mapMemory();
            defer staging.unmapMemory();

            @memcpy(staging_mem, elem);

            try buf.copy(staging.buffer(), self.buffer(), self.buf.dev);
        }

        pub fn deinit(ctx: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.buf.deinit();
        }

        pub fn bind(ctx: *anyopaque, cmd_buf: *const CommandBuffer) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.buf.dev.pr_dev.cmdBindIndexBuffer(cmd_buf.h_cmd_buffer, self.buf.h_buf, 0, index_type);
        }

        pub fn buffer(self: *Self) AnyBuffer {
            return AnyBuffer{
                .cfg = &Inner.cfg,
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
    };
}
