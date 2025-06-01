const std = @import("std"); 
const ray = @import("ray");

const glfw = @import("glfw.zig");

const Window = glfw.Window;
pub fn main() !void {

    glfw.init() catch |err| {
        std.debug.print("Failed to initialize GLFW\n", .{});
        return err;
    };
    defer glfw.terminate();
    
    Window.hints(.{
        .{ glfw.CLIENT_API, glfw.NO_API },
        .{ glfw.RESIZABLE, glfw.FALSE },
    });

    var window = Window.create(900, 600, "Test Window", null, null) catch |err| {
        std.debug.print("Failed to create GLFW Window\n", .{});
        return err;
    };
    defer window.destroy();

    // barebones package manager test -- will replace with proper testing suites later I guess
    glfw.vulkanSupported() catch |err| {
        std.debug.print("Could not load Vulkan\n", .{});
        return err;
    };

    try ray.testInstance();

    while (!window.shouldClose()) {
        glfw.glfwPollEvents();
    }

    std.debug.print("You win!\n",.{});
}


