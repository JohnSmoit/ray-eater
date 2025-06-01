const c = @cImport({
    @cInclude("GLFW/glfw3.h");
});

pub const TRUE = c.GLFW_TRUE;
pub const FALSE = c.GLFW_FALSE;

// Window Hint Values
pub const CLIENT_API = c.GLFW_CLIENT_API;
pub const NO_API = c.GLFW_NO_API;
pub const RESIZABLE = c.GLFW_RESIZABLE;


pub const GLFWwindow = c.GLFWwindow;

fn ErrorOnFalse(comptime func: fn() callconv(.c) c_int, comptime set: type, err: set) (fn() set!void) {
    const wrapperType = struct {
        pub fn wrapper() set!void {
            switch(func()) {
                FALSE => return err,
                else => return
            } 
        }
    };

    return wrapperType.wrapper;
}

pub const init = ErrorOnFalse(c.glfwInit, error {GLFWInitFailed}, error.GLFWInitFailed);
pub const terminate = c.glfwTerminate;
pub const vulkanSupported = ErrorOnFalse(c.glfwVulkanSupported, error {VulkanUnsupported}, error.VulkanUnsupported);
pub const glfwGetRequiredInstanceExtensions = c.glfwGetRequiredInstanceExtensions;
pub const glfwGetFramebufferSize = c.glfwGetFramebufferSize;
pub const glfwPollEvents = c.glfwPollEvents;

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
            .handle = glfwCreateWindow(width, height, title, monitor,  share)
                orelse return error.WindowCreateFailed,
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
