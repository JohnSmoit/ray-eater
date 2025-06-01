const std = @import("std"); 
const glfw = @import("glfw.zig");

pub fn main() !void {

    if (glfw.glfwInit() != glfw.GLFW_TRUE) return error.GLFWInitFailed;
    defer glfw.glfwTerminate();

    const window = glfw.glfwCreateWindow(900, 600, "Test Window", null, null) orelse return error.GLFWWindowFailed;
    defer glfw.glfwDestroyWindow(window);
    while (glfw.glfwWindowShouldClose(window) != glfw.GLFW_TRUE) {
        glfw.glfwPollEvents();
    }
}


