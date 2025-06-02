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
    errdefer glfw.terminate();
    
    Window.hints(.{
        .{ glfw.CLIENT_API, glfw.NO_API },
        .{ glfw.RESIZABLE, glfw.FALSE },
    });

    var window = Window.create(900, 600, "Test Window", null, null) catch |err| {
        std.debug.print("Failed to create GLFW Window\n", .{});
        return err;
    };
    defer window.destroy();

    glfw.vulkanSupported() catch |err| {
        std.debug.print("Could not load Vulkan\n", .{});
        return err;
    };

    // apparently GeneralPurposeAllocator is deprecated so I guess I'll try this one? 
    var gpa = std.heap.DebugAllocator(.{}).init;

    ray.setLoaderFunction(glfw.glfwGetInstanceProcAddress);

    var extensionCount: u32 = undefined;
    ray.setRequiredExtensions(@ptrCast(glfw.getRequiredInstanceExtensions(&extensionCount)[0..extensionCount]));
    try ray.testInit(gpa.allocator());

    while (!window.shouldClose()) {
        glfw.pollEvents();
        try ray.testLoop();
    }

    ray.testDeinit();

    std.debug.print("You win!\n",.{});
}


