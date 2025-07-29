const api = @import("api.zig");
const buf_api = @import("buffer.zig");

const GenericBuffer = buf_api.GenericBuffer;
const AnyBuffer = buf_api.AnyBuffer;
const Context = @import("../context.zig");

const CommandBuffer = api.CommandBuffer;

pub fn ComptimeStorageBuffer(comptime T: type) type {
    return struct {
        const InnerType = buf_api.GenericBuffer(T, .{
            .memory = .{ .device_local_bit = true },
            .usage = .{
                .transfer_dst_bit = true,
                .storage_buffer_bit = true,
            },
        });
        const Self = @This();

        buf: InnerType,

        pub fn create(ctx: *const Context, size: usize) !Self {
            return .{
                .buf = try InnerType.create(ctx, size),
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

            try buf_api.copy(staging.buffer(), self.buffer(), self.buf.dev);
        }

        pub fn bind(ctx: *anyopaque, cmd_buf: *const CommandBuffer) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.buf.dev.pr_dev.cmdBindVertexBuffers(
                cmd_buf.h_cmd_buffer,
                0,
                1,
                &.{&self.buf.h_buf},
                &.{0},
            );
        }
        pub fn deinit(ctx: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.buf.deinit();
        }

        pub fn buffer(self: *Self) AnyBuffer {
            return AnyBuffer{
                .cfg = &InnerType.cfg,
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
