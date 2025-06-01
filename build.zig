const std = @import("std");

fn getGLFWDep(b: *std.Build) *std.Build.Dependency {
    // TODO: Swap dependency based on platform so the correct binary is linked
    return b.dependency("glfw_windows", .{});
}

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    // module definition for the Ray Eater Library
    // All of the actual "meat" of the renderer is in the library
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // module definition for the temporary test application
    // This is only intended to exist during early development/prototyping to
    // speed up smoke and fuzz testing 
    const app_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    app_mod.addImport("ray", lib_mod);

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "RayEater",
        .root_module = lib_mod,
    });

    const app = b.addExecutable(.{
        .name = "RayEater_App",
        .root_module = app_mod,
    });

    // Link and install GLFW binaries

    app.linkSystemLibrary("user32");
    app.linkSystemLibrary("gdi32");
    app.linkSystemLibrary("shell32");
    const glfw_dep = getGLFWDep(b);

    app.addIncludePath(glfw_dep.path("include"));
    app.addObjectFile(glfw_dep.path("lib-mingw-w64/libglfw3.a"));
    
    app.linkLibC();
    b.installArtifact(lib);
    b.installArtifact(app);

    const run_cmd = b.addRunArtifact(app);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
