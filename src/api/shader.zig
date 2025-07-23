const std = @import("std");
const rshc = @import("rshc");

const vk = @import("vulkan");

pub const Context = @import("../context.zig");
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.shader);

const DeviceHandler = @import("base.zig").DeviceHandler;

pub const Module = struct {
    pub const Stage = rshc.Stage;

    fn toShaderStageFlags(stage: Stage) vk.ShaderStageFlags {
        return switch (stage) {
            .Fragment => vk.ShaderStageFlags{ .fragment_bit = true },
            .Vertex => vk.ShaderStageFlags{ .vertex_bit = true },
            .Compute => vk.ShaderStageFlags{ .compute_bit = true },
        };
    }

    module: vk.ShaderModule = .null_handle,
    pipeline_info: vk.PipelineShaderStageCreateInfo = undefined,
    pr_dev: *const vk.DeviceProxy = undefined,

    pub fn initFromBytes(ctx: *const Context, bytes: []const u8, stage: Stage) !Module {
        const dev: *const DeviceHandler = ctx.env(.dev);
        const module = try dev.pr_dev.createShaderModule(&.{
            .code_size = bytes.len,
            .p_code = @as([*]const u32, @alignCast(@ptrCast(bytes.ptr))),
        }, null);

        const pipeline_info = vk.PipelineShaderStageCreateInfo{
            .stage = toShaderStageFlags(stage),
            .module = module,
            .p_name = "main",
        };

        return Module{
            .module = module,
            .pipeline_info = pipeline_info,
            .pr_dev = &dev.pr_dev,
        };
    }

    pub fn fromSourceFile(
        ctx: *const Context,
        alloc: Allocator,
        filename: []const u8,
        stage: Stage,
    ) !Module {
        var arena = std.heap.ArenaAllocator.init(alloc);

        defer arena.deinit();
        const allocator = arena.allocator();

        const compilation_result = rshc.compileShaderAlloc(
            filename,
            stage,
            allocator,
        );

        const compiled_bytes: []const u8 = switch (compilation_result) {
            .Success => |val| val,
            .Failure => |val| fail: {
                log.err("Failed to load shader data due to {!}\nReason: {s}", .{
                    val.status,
                    val.message orelse "Unknown",
                });
                break :fail &.{};
            }
        };

        if (compiled_bytes.len == 0) {
            return error.ShaderCompilationError;
        }

        if (@rem(compiled_bytes.len, @sizeOf(u32)) != 0) {
            log.warn("Warning: SPIR-V bytes for {s} do not meet alignment requirements (off by {d})", .{
                filename,
                @rem(compiled_bytes.len, @sizeOf(u32)),
            });
        }

        log.debug("succesfully compiled shader", .{});

        return initFromBytes(ctx, compiled_bytes, stage);
    }

    pub fn deinit(self: *const Module) void {
        self.pr_dev.destroyShaderModule(self.module, null);
    }
};
