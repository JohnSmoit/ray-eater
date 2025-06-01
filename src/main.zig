const std = @import("std"); 
const ray = @import("ray");

const glfw = @import("glfw.zig");

pub fn main() !void {

    if (glfw.glfwInit() != glfw.GLFW_TRUE) return error.GLFWInitFailed;
    defer glfw.glfwTerminate();

    const window = glfw.glfwCreateWindow(900, 600, "Test Window", null, null) orelse return error.GLFWWindowFailed;
    defer glfw.glfwDestroyWindow(window);

    // barebones package manager test -- will replace with proper testing suites later I guess
    if (glfw.glfwVulkanSupported() != glfw.GLFW_TRUE) {
        std.debug.print("Could not load Vulkan", .{});
    }
    try ray.testInstance();
    while (glfw.glfwWindowShouldClose(window) != glfw.GLFW_TRUE) {
        glfw.glfwPollEvents();
    }

}


