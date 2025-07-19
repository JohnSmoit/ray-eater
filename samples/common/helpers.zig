//! Common helperss used for multiple sample executables

const std = @import("std");
const vk = @import("vulkan");

const glfw = @import("glfw");

const Window = glfw.Window;

pub fn makeBasicWindow(w: u32, h: u32, name: []const u8) !Window {
    glfw.init() catch |err| {
        std.debug.print("Failed to initialize GLFW\n", .{});
        return err;
    };

    Window.hints(.{
        .{ glfw.CLIENT_API, glfw.NO_API },
        .{ glfw.RESIZABLE, glfw.FALSE },
    });

    const window = Window.create(@intCast(w), @intCast(h), name.ptr, null, null) catch |err| {
        std.debug.print("Failed to create GLFW Window\n", .{});
        return err;
    };

    return window;
}

pub fn glfwInstanceExtensions() [][*:0]const u8 {
    var count: u32 = 0;
    return @ptrCast(glfw.getRequiredInstanceExtensions(&count)[0..count]);
}

pub fn windowExtent(win: *const Window) vk.Extent2D {
    const dims = win.dimensions();
    return vk.Extent2D{
        .width = dims.width,
        .height = dims.height,
    };
}
