const std = @import("std");
const ray = @import("ray");

const glfw = @import("glfw");

const Context = ray.Context;

const Window = glfw.Window;

fn makeBasicWindow(w: u32, h: u32, name: []const u8) !Window {
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

fn glfwInstanceExtensions() [][*:0]const u8 {
    var count: u32 = 0;
    return @ptrCast(glfw.getRequiredInstanceExtensions(&count)[0..count]);
}

pub fn main() !void {
    var window = try makeBasicWindow(900, 600, "Test Window");
    defer glfw.terminate();
    defer window.destroy();

    glfw.vulkanSupported() catch |err| {
        std.debug.print("Could not load Vulkan\n", .{});
        return err;
    };

    var gpa = std.heap.DebugAllocator(.{}).init;  

    window.show();

    var extensionCount: u32 = undefined;
    ray.setRequiredExtensions(@ptrCast(glfw.getRequiredInstanceExtensions(&extensionCount)[0..extensionCount]));
    ray.setWindow(&window);

    try ray.testInit(gpa.allocator());
    defer ray.testDeinit();

    while (!window.shouldClose()) {
        glfw.pollEvents();
        try ray.testLoop();
    }


    std.debug.print("You win!\n", .{});
}

const expect = std.testing.expect;

var testing_allocator = std.heap.DebugAllocator(.{.safety = true}).init;

test "context initialization" {
    const alloc = testing_allocator.allocator();
    const window = try makeBasicWindow(900, 600, "Actual Test Window");
    defer glfw.terminate();
    defer window.destroy();

    const ctx = try Context.init(alloc, .{
        .window = &window,
        .loader = glfw.glfwGetInstanceProcAddress,
        .inst_extensions = glfwInstanceExtensions(),
    });
    defer ctx.deinit();
}

test "environment querying" {
    const alloc = testing_allocator.allocator();
    const window = try makeBasicWindow(900, 600, "Actual Actual Test Window");
    defer glfw.terminate();
    defer window.destroy();

    const ctx = try Context.init(alloc, .{
        .window = &window,
        .loader = glfw.glfwGetInstanceProcAddress,
        .inst_extensions = glfwInstanceExtensions(),
    });
    defer ctx.deinit();

    const global_interface = ctx.env(.gi);
    const instance_interface = ctx.env(.ii);
    const dev_interface = ctx.env(.di);

    std.debug.print("global_interface type: {s}\n", .{@typeName(@TypeOf(global_interface))});
    std.debug.print("instance_interface type: {s}\n", .{@typeName(@TypeOf(instance_interface))});
    std.debug.print("dev_interface type: {s}\n", .{@typeName(@TypeOf(dev_interface))});

    
    //TODO: Do some rudimentary vulkan API test call.
}

test "basic vulkan type creation" {
    try expect(true);
}
