const c = @cImport({
    @cInclude("GLFW/glfw3.h");
});

pub const GLFW_TRUE = c.GLFW_TRUE;
pub const GLFW_FALSE = c.GLFW_FALSE;
pub const GLFW_CLIENT_API = c.GLFW_CLIENT_API;
pub const GLFW_NO_API = c.GLFW_NO_API;

pub const GLFWwindow = c.GLFWwindow;

pub const glfwInit = c.glfwInit;
pub const glfwTerminate = c.glfwTerminate;
pub const glfwVulkanSupported = c.glfwVulkanSupported;
pub const glfwWindowHint = c.glfwWindowHint;
pub const glfwCreateWindow = c.glfwCreateWindow;
pub const glfwDestroyWindow = c.glfwDestroyWindow;
pub const glfwWindowShouldClose = c.glfwWindowShouldClose;
pub const glfwGetRequiredInstanceExtensions = c.glfwGetRequiredInstanceExtensions;
pub const glfwGetFramebufferSize = c.glfwGetFramebufferSize;
pub const glfwPollEvents = c.glfwPollEvents;
