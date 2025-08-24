//! Type for uniform buffers

const buf_api = @import("buffer.zig");

const DeviceHandler = @import("base.zig").DeviceHandler;
const CommandBuffer = @import("command_buffer.zig");
const Context = @import("../context.zig");

const AnyBuffer = buf_api.AnyBuffer;
const GenericBuffer = buf_api.GenericBuffer;

/// More like undefined behaviour object LMAO
pub fn UniformBuffer(T: type) type {
    return struct {
        const Self = @This();
        const InnerBuffer = GenericBuffer(T, .{ .memory = .{
            .host_visible_bit = true,
            .host_coherent_bit = true,
        }, .usage = .{
            // FIXME: No need this vvv 
            .transfer_dst_bit = true,
            .uniform_buffer_bit = true,
        } });

        buf: InnerBuffer,
        mem: []T,

        pub fn create(ctx: *const Context) !Self {
            var buf = try InnerBuffer.create(ctx, 1);
            errdefer buf.deinit(); // conditionally deinits allocated memory if it exists

            const mem = try buf.mapMemory();
            errdefer buf.unmapMemory();

            return Self{ .mem = mem, .buf = buf };
        }

        pub fn bind(self: *Self, cmd_buf: *const CommandBuffer) void {
            // No-Op

            _ =  self;
            _ = cmd_buf;
        }

        pub fn buffer(self: *Self) AnyBuffer {
            return AnyBuffer{
                .cfg = &InnerBuffer.cfg,
                .handle = self.buf.h_buf,
                .ptr = self,
                .size = self.buf.bytesSize(),
                .vtable = buf_api.AutoVTable(Self),
            };
        }

        pub fn setData(self: *Self, data: *const anyopaque) !void {
            const elem: []const T = @as([*]const T, @ptrCast(@alignCast(data)))[0..self.buf.size];

            @memcpy(self.mem, elem);
        }

        pub fn deinit(self: *Self) void {
            self.buf.unmapMemory();
            self.buf.deinit();
        }
    };
}


