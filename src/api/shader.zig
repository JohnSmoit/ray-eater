const std = @import("std");
const rshc = @import("rshc");

const vk = @import("vulkan");

const api = @import("vulkan.zig");

pub const Stage = rshc.Stage;

const log = std.log.scoped(.shader);

pub fn toShaderStageFlags(stage: Stage) vk.ShaderStageFlags {
    return switch (stage) {
        .Fragment => vk.ShaderStageFlags{ .fragment_bit = true },
        .Vertex => vk.ShaderStageFlags{ .vertex_bit = true },
    };
}

pub const Module = struct {
    module: vk.ShaderModule = .null_handle,
    pipeline_info: vk.PipelineShaderStageCreateInfo = undefined,
    pr_dev: *const vk.DeviceProxy = undefined,

    pub fn from_source_file(stage: Stage, filename: []const u8, dev: *const api.Device) !Module {
        var arena = std.heap.ArenaAllocator.init(dev.ctx.allocator);
        
        // Arena's deinit always frees all allocated memory, so no need
        // to worry about indiviudal allocations
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

        const pipeline_info = vk.PipelineShaderStageCreateInfo {
            .stage = toShaderStageFlags(stage),
            .module = module,
            .p_name  = "main",
        };

        return Module {
            .module = module,
            .pipeline_info = pipeline_info,
            .pr_dev = &dev.pr_dev,
        };
    }

    pub fn deinit(self: *const Module) void {
        self.pr_dev.destroyShaderModule(self.module, null);
    }
};
