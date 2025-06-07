const c = @cImport({
    @cDefine("GLFW_INCLUDE_NONE", {});
    @cInclude("GLFW/glfw3.h");
});

// as much as I was hoping things would stay modularized early on,
// we unfortunately need to know what a VkInstance is in order to be able to
// manually import GLFW's loader function, which means gross type exports for the time being...

const vk = @import("vulkan");

pub const TRUE = c.GLFW_TRUE;
pub const FALSE = c.GLFW_FALSE;

// Window Hint Values
pub const CLIENT_API = c.GLFW_CLIENT_API;
pub const NO_API = c.GLFW_NO_API;
pub const RESIZABLE = c.GLFW_RESIZABLE;

pub const GLFWwindow = c.GLFWwindow;

fn ErrorOnFalse(comptime func: fn () callconv(.c) c_int, comptime err: anytype) (fn () @TypeOf(err)!void) {
    const errorSetType = @TypeOf(err);
    const wrapperType = struct {
        pub fn wrapper() errorSetType!void {
            switch (func()) {
                FALSE => return err,
                else => return
            }
        }
    };

    return wrapperType.wrapper;
}

pub extern fn glfwGetInstanceProcAddress(instance: vk.Instance, name: [*:0]const u8) vk.PfnVoidFunction;
pub extern fn glfwCreateWindowSurface(instance: vk.Instance, window: *Window, allocation_callbacks: ?*const vk.AllocationCallbacks, surface: *vk.SurfaceKHR) vk.Result;

pub const init = ErrorOnFalse(c.glfwInit, error.GLFWInitFailed);
pub const terminate = c.glfwTerminate;
pub const vulkanSupported = ErrorOnFalse(c.glfwVulkanSupported, error.VulkanUnsupported);
pub const getRequiredInstanceExtensions = c.glfwGetRequiredInstanceExtensions;
pub const getFramebufferSize = c.glfwGetFramebufferSize;
pub const pollEvents = c.glfwPollEvents;

pub const createWindowSurface = c.glfwCreateWindowSurface;

const glfwDestroyWindow = c.glfwDestroyWindow;
const glfwWindowShouldClose = c.glfwWindowShouldClose;
const glfwCreateWindow = c.glfwCreateWindow;
const glfwWindowHint = c.glfwWindowHint;

pub const Window = struct {
    handle: *GLFWwindow,

    pub fn destroy(self: *Window) void {
        glfwDestroyWindow(self.handle);
    }

    pub fn shouldClose(self: *Window) bool {
        return glfwWindowShouldClose(self.handle) == TRUE;
    }

    pub fn create(width: c_int, height: c_int, title: [*c]const u8, monitor: ?*c.GLFWmonitor, share: ?*GLFWwindow) !Window {
        return .{
            .handle = glfwCreateWindow(width, height, title, monitor, share) orelse return error.WindowCreateFailed,
        };
    }

    pub fn hints(values: anytype) void {
        inline for (values, 0..) |v, i| {
            const hintName = @as(c_int, v[0]);
            const hintValue = @as(c_int, v[1]);

            glfwWindowHint(hintName, hintValue);
            _ = i;
        }
    }
};
