const std = @import("std");
const ray = @import("ray");

const glfw = @import("glfw");

const Window = glfw.Window;

pub fn main() !void {
    const ctx = ray.Context.init();
    std.debug.print("Returned type: {s}\n", .{@typeName(@TypeOf(ctx.env(.di)))});

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

    glfw.vulkanSupported() catch |err| {
        std.debug.print("Could not load Vulkan\n", .{});
        return err;
    };

    window.show();

    // apparently GeneralPurposeAllocator is deprecated so I guess I'll try this one?
    var gpa = std.heap.DebugAllocator(.{}).init;

    var extensionCount: u32 = undefined;
    ray.setRequiredExtensions(@ptrCast(glfw.getRequiredInstanceExtensions(&extensionCount)[0..extensionCount]));
    ray.setWindow(&window);
    try ray.testInit(gpa.allocator());

    while (!window.shouldClose()) {
        glfw.pollEvents();
        try ray.testLoop();
    }

    ray.testDeinit();

    std.debug.print("You win!\n", .{});
}
