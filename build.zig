const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    // module definition for the Ray Eater Library
    // All of the actual "meat" of the renderer is in the library
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/ray/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const vulkan_mod = b.dependency(
        "vulkan",
        .{
            .registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml"),
        },
    ).module("vulkan-zig");

    const rshc_mod = b.dependency("RshLang", .{}).module("rshc");

    // module definition for the temporary test application
    // This is only intended to exist during early development/prototyping to
    // speed up smoke and fuzz testing
    const app_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const glfw_mod = b.createModule(.{
        .root_source_file = b.path("src/glfw.zig"),
        .target = target,
        .optimize = optimize,
    });

    const glfw_dep = b.dependency("glfw_windows", .{});

    app_mod.addImport("ray", lib_mod);
    app_mod.addImport("glfw", glfw_mod);

    lib_mod.addImport("vulkan", vulkan_mod);
    lib_mod.addImport("glfw", glfw_mod);
    lib_mod.addImport("rshc", rshc_mod);

    glfw_mod.addObjectFile(glfw_dep.path("lib-mingw-w64/libglfw3.a"));
    glfw_mod.addImport("vulkan", vulkan_mod);

    glfw_mod.linkSystemLibrary("user32", .{});
    glfw_mod.linkSystemLibrary("gdi32", .{});
    glfw_mod.linkSystemLibrary("shell32", .{});
    glfw_mod.addIncludePath(glfw_dep.path("include"));

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "RayEater",
        .root_module = lib_mod,
    });

    const app = b.addExecutable(.{
        .name = "RayEater_App",
        .root_module = app_mod,
    });

    const test_mod = b.createModule(.{
        .root_source_file = b.path("test/test_math.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addImport("ray", lib_mod);

    const lib_tests = b.addTest(.{
        .root_module = test_mod,
        .link_libc = true,
    });

    // temporary hard dep of GLFW to the library module, since I don't
    // want to deal with all the platorm specific runtime dyn linking shit (yet)

    app.linkLibC();

    b.installArtifact(lib);
    b.installArtifact(app);

    const run_cmd = b.addRunArtifact(app);
    const test_cmd = b.addRunArtifact(lib_tests);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    const test_step = b.step("test", "Run all unit tests at once");

    run_step.dependOn(&run_cmd.step);
    test_step.dependOn(&test_cmd.step);
}
