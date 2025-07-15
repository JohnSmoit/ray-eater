const std = @import("std");
const rshc = @import("rshc");

const vk = @import("vulkan");

pub const Stage = rshc.Stage;
pub const Context = @import("../context.zig");
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.shader);

const DeviceHandler = @import("base.zig").DeviceHandler;

pub fn toShaderStageFlags(stage: Stage) vk.ShaderStageFlags {
    return switch (stage) {
        .Fragment => vk.ShaderStageFlags{ .fragment_bit = true },
        .Vertex => vk.ShaderStageFlags{ .vertex_bit = true },
    };
}

pub const Module = struct {
    pub const Config = struct {
        stage: Stage,
        filename: []const u8,
    };

    module: vk.ShaderModule = .null_handle,
    pipeline_info: vk.PipelineShaderStageCreateInfo = undefined,
    pr_dev: *const vk.DeviceProxy = undefined,

    pub fn fromSourceFile(
        ctx: *const Context,
        alloc: Allocator,
        config: Config,
    ) !Module {
        const dev: *const DeviceHandler = ctx.env(.dev);
        var arena = std.heap.ArenaAllocator.init(alloc);

        defer arena.deinit();
        const allocator = arena.allocator();

        const compilation_result = rshc.compileShaderAlloc(
            config.filename,
            config.stage,
            allocator,
        );

        const compiled_bytes: []const u8 = switch (compilation_result) {
            .Success => |val| val,
            .Failure => |val| fail: {
                log.err("Failed to load shader data due to {!}\nReason: {s}", .{
                    val.status,
                    val.message orelse "Unknown",
                });
                break :fail &[0]u8{};
            }
        };

        if (compiled_bytes.len == 0) {
            return error.ShaderCompilationError;
        }

        const module = try dev.pr_dev.createShaderModule(&.{
            .code_size = compiled_bytes.len,
            .p_code = @alignCast(@ptrCast(compiled_bytes.ptr)),
        }, null);

        const pipeline_info = vk.PipelineShaderStageCreateInfo{
            .stage = toShaderStageFlags(config.stage),
            .module = module,
            .p_name = "main",
        };

        return Module{
            .module = module,
            .pipeline_info = pipeline_info,
            .pr_dev = &dev.pr_dev,
        };
    }

    pub fn deinit(self: *const Module) void {
        self.pr_dev.destroyShaderModule(self.module, null);
    }
};
