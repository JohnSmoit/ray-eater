//! Just some basic helpers for asset loading such as textures and shaders.

const std = @import("std");
const vk = @import("vulkan");

const img = @import("zigimg");
const shaderc = @import("shaderc_c.zig");

const Allocator = std.mem.Allocator;

const FileError = error {
};
const ShaderLoadError = error {
} | FileError;

const ShaderStage = enum {
    Vertex,
    Fragment,
    Compute
};

pub fn loadShader(
    stage: ShaderStage,
    bytes: []const u8,
) ShaderLoadError!vk.Shader {
    _ = stage;
    _ = bytes;

    return undefined;
}

pub fn loadShaderFromFile(
    stage: ShaderStage,
    path: []const u8,
    allocator: Allocator,
) ShaderLoadError!vk.Shader {
    _ = stage;
    _ = path;
    _ = allocator;

    return undefined;
}

// Lazy me so this'll just return raw bytes
pub fn loadTextureFromFile(
    path: []const u8,
) FileError![]u8 {
    _ = path;

    return undefined;
}
