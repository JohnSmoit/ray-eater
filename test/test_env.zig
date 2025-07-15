const std = @import("std");

const expect = std.testing.expect;

var testing_allocator = std.heap.DebugAllocator(.{ .safety = true }).init;

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

    const global_interface: *const ray.api.GlobalInterface = ctx.env(.gi);
    const instance_interface = ctx.env(.ii);
    const dev_interface = ctx.env(.di);

    std.debug.print("global_interface type: {s}\n", .{@typeName(@TypeOf(global_interface))});
    std.debug.print("instance_interface type: {s}\n", .{@typeName(@TypeOf(instance_interface))});
    std.debug.print("dev_interface type: {s}\n", .{@typeName(@TypeOf(dev_interface))});

    //TODO: Do some rudimentary vulkan API test call.
    const available = global_interface.enumerateInstanceExtensionPropertiesAlloc(
        null,
        alloc,
    ) catch {
        return error.ExtensionEnumerationFailed;
    };
    defer alloc.free(available);
}

test "basic vulkan type creation" {
    try expect(true);
}
