const vk = @import("vulkan");

const std = @import("std");
const api = @import("vulkan.zig");

const log = std.log.scoped(.buffer);
const meth = @import("../math.zig");
const util = @import("../util.zig");

const TypeInfo = std.builtin.Type;
const StructInfo = std.builtin.Type.Struct;

const assert = std.debug.assert;

pub const Config = struct {
    usage: vk.BufferUsageFlags = .{},
    memory: vk.MemoryPropertyFlags = .{},
};

const VTable = struct {
    bind: *const (fn (*anyopaque, *const api.CommandBufferSet) void) = undefined,

    // this is kinda gross, maybe consider something other than type erasing here...
    setData: *const (fn (*anyopaque, *const anyopaque) anyerror!void) = undefined,
    deinit: *const (fn (*anyopaque) void) = undefined,
};

/// generic buffer interface, exposes common functionality
/// for buffer operations such as binding, setting data, and
/// lifecycle functions. These are directly meant to be
/// called by users, unlike the lower-level generic buffer type
pub const AnyBuffer = struct {
    /// the type-erased inner buffer
    /// The lifecycle of this pointer must exceed the lifespan
    /// of the interface wrapper
    ptr: *anyopaque,
    handle: vk.Buffer,
    size: usize,

    /// Used mostly as a hint to detect potentially invalid
    /// usage
    cfg: *const Config,
    vtable: *const VTable,

    pub fn bind(self: AnyBuffer, cmd_buf: *const api.CommandBufferSet) void {
        self.vtable.bind(self.ptr, cmd_buf);
    }

    pub fn setData(self: AnyBuffer, data: *const anyopaque) !void {
        try self.vtable.setData(self.ptr, data);
    }

    pub fn deinit(self: AnyBuffer) void {
        self.vtable.deinit(self.ptr);
    }
};

pub fn copy(src: AnyBuffer, dst: AnyBuffer, dev: *const api.Device) !void {
    assert(src.cfg.usage.contains(.{ .transfer_src_bit = true }));
    assert(dst.cfg.usage.contains(.{ .transfer_dst_bit = true }));

    const transfer_cmds = try api.CommandBufferSet.oneShot(dev);
    defer transfer_cmds.deinit();

    dev.pr_dev.cmdCopyBuffer(
        transfer_cmds.h_cmd_buffer,
        src.handle,
        dst.handle,
        1,
        util.asManyPtr(vk.BufferCopy, &.{
            .src_offset = 0,
            .dst_offset = 0,
            .size = src.size,
        }),
    );

    try transfer_cmds.end();
}

pub fn StagingType(T: type) type {
    return GenericBuffer(T, .{
        .memory = .{
            .host_visible_bit = true,
            .host_coherent_bit = true,
        },
        .usage = .{
            .transfer_src_bit = true,
        },
    });
}


/// provides basic buffer functionality and not much else
/// Mean't to be composed into specializations of various buffer types
/// this is a sort of "Helper" meant to lessen code duplication
/// for operations that all buffers basically do the same with an opt-in
/// (users choose which functions to use) approach
pub fn GenericBuffer(T: type, comptime config: Config) type {
    return struct {
        const Self = @This();

        pub const element_size: usize = @sizeOf(T);
        pub const cfg = config;

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
                    .usage = config.usage,
                    .sharing_mode = .exclusive,
                }, null),
                .size = size,
                .dev = dev,
            };
            errdefer dev.pr_dev.destroyBuffer(buf.h_buf, null);

            buf.h_mem = try Self.allocateMemory(dev, buf.h_buf);
            log.debug("Successfully allocated buffer memory!", .{});

            return buf;
        }

        pub fn bytesSize(self: *const Self) usize {
            return element_size * self.size;
        }

        pub fn allocateMemory(dev: *const api.Device, h_buf: vk.Buffer) !vk.DeviceMemory {
            const pr_dev = &dev.pr_dev;

            const mem_reqs = pr_dev.getBufferMemoryRequirements(h_buf);
            const chosen_mem = try dev.findMemoryTypeIndex(mem_reqs, config.memory);

            const h_mem = try pr_dev.allocateMemory(&.{
                .allocation_size = mem_reqs.size,
                .memory_type_index = chosen_mem,
            }, null);
            errdefer pr_dev.freeMemory(h_mem, null);

            try pr_dev.bindBufferMemory(h_buf, h_mem, 0);

            return h_mem;
        }

        pub fn mapMemory(self: *Self) ![]T {
            return @as([*]T, @alignCast(@ptrCast(try self.dev.pr_dev.mapMemory(
                self.h_mem.?,
                0,
                self.bytesSize(),
                .{},
            ))))[0..self.size];
        }

        pub fn unmapMemory(self: *Self) void {
            self.dev.pr_dev.unmapMemory(self.h_mem.?);
        }

        pub fn createStaging(self: *Self) !StagingType(T) {
            const Staging = StagingType(T);
            assert(config.usage.contains(.{ .transfer_dst_bit = true }));

            const staging_buf = try Staging.create(self.dev, self.size);
            return staging_buf;
        }

        pub fn buffer(self: *Self) AnyBuffer {
            return AnyBuffer {
                .cfg = &Self.cfg,
                .handle = self.h_buf,
                .ptr = self,
                .vtable = &.{
                    .setData = Self.setData,
                }, 
                .size = self.bytesSize(),
            };
        }


        pub fn setData(ctx: *anyopaque, data: *const anyopaque) !void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            const elem: []const T = @as([*]const T, @ptrCast(@alignCast(data)))[0..self.size];

            const mem = try self.mapMemory();

            @memcpy(mem, elem);
            self.unmapMemory();
        }

        pub fn copyTo(self: *Self, dest: AnyBuffer) !void {
            assert(config.usage.contains(.{ .transfer_src_bit = true }));
            assert(dest.config.usage.contains(.{ .transfer_dst_bit = true }));

            const transfer_cmds = try api.CommandBufferSet.oneShot(self.dev);
            defer transfer_cmds.deinit();

            self.dev.pr_dev.cmdCopyBuffer(
                transfer_cmds.h_cmd_buffer,
                self.h_buf,
                dest.h_buf,
                1,
                util.asManyPtr(vk.BufferCopy, &.{
                    .src_offset = 0,
                    .dst_offset = 0,
                    .size = self.bytesSize(),
                }),
            );

            try transfer_cmds.end();
        }

        pub fn deinit(self: *const Self) void {
            self.dev.pr_dev.destroyBuffer(self.h_buf, null);

            if (self.h_mem != null) {
                self.dev.pr_dev.freeMemory(self.h_mem.?, null);
            }
        }
    };
}
