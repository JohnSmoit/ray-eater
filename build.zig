const std = @import("std");

const Module = std.Build.Module;
const ResolvedTarget = std.Build.ResolvedTarget;
const OptimizeMode = std.builtin.OptimizeMode;

const BuildOpts = struct {
    target: ?ResolvedTarget,
    optimize: ?OptimizeMode,
};

const Dependencies = struct {
    rshc: *Module,
    vulkan: *Module,
    glfw: *Module,
};

fn resolveGLFWSystemDeps(m: *Module) void {
    //TODO: link proper runtime modules for non-windows
    m.linkSystemLibrary("user32", .{});
    m.linkSystemLibrary("gdi32", .{});
    m.linkSystemLibrary("shell32", .{});
}
// Build project dependencies
fn buildDeps(b: *std.Build, opts: BuildOpts) Dependencies {
    const vulkan_mod = b.dependency(
        "vulkan",
        .{
            .registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml"),
        },
    ).module("vulkan-zig");
    const rshc_mod = b.dependency("RshLang", .{}).module("rshc");
    const glfw_dep = b.dependency("glfw_windows", .{});

    // GLFW is a special beast...
    const glfw_mod = b.createModule(.{
        .root_source_file = b.path("src/glfw.zig"),
        .target = opts.target,
        .optimize = opts.optimize,
    });

    glfw_mod.addObjectFile(glfw_dep.path("lib-mingw-w64/libglfw3.a"));
    glfw_mod.addImport("vulkan", vulkan_mod);
    glfw_mod.addIncludePath(glfw_dep.path("include"));
    glfw_mod.link_libc = true;

    resolveGLFWSystemDeps(glfw_mod);

    return .{
        .rshc = rshc_mod,
        .vulkan = vulkan_mod,
        .glfw = glfw_mod,
    };
}

fn buildLibrary(
    b: *std.Build,
    deps: Dependencies,
    opts: BuildOpts,
) *Module {
    // module definition for the Ray Eater Library
    // All of the actual "meat" of the renderer is in the library
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = opts.target,
        .optimize = opts.optimize,
    });

    lib_mod.addImport("vulkan", deps.vulkan);
    lib_mod.addImport("rshc", deps.rshc);
    lib_mod.addImport("glfw", deps.glfw);

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "RayEater",
        .root_module = lib_mod,
    });

    b.installArtifact(lib);

    return lib_mod;
}

const SampleEntry = struct {
    name: []const u8,
    path: []const u8,
};
const sample_files = [_]SampleEntry{
    .{ .name = "basic_planes", .path = "basic_planes.zig" },
    .{ .name = "basic_compute", .path = "basic_compute.zig" },
    .{ .name = "test_sample", .path = "test_sample.zig" },
};
/// build sample applications which demonstrate the usage
/// and features of the library
fn buildSamples(
    b: *std.Build,
    lib_mod: *Module,
    deps: Dependencies,
    opts: BuildOpts,
) void {
    const build_sample = b.option(
        []const u8,
        "sample",
        "specify sample to build and run",
    );
    if (build_sample) |sample_name| {
        var sample_path: ?[]const u8 = null;

        for (sample_files) |f| {
            if (std.mem.order(u8, sample_name, f.name) == .eq) {
                sample_path = f.path;
                break;
            }
        }

        if (sample_path == null) return;

        const sample_mod = b.createModule(.{
            .root_source_file = b.path(b.pathJoin(&.{
                "samples",
                sample_path.?,
            })),
            .optimize = opts.optimize,
            .target = opts.target,
        });

        sample_mod.addImport("ray", lib_mod);
        sample_mod.addImport("glfw", deps.glfw);

        const sample_exe = b.addExecutable(.{
            .name = sample_name,
            .root_module = sample_mod,
            .optimize = opts.optimize orelse .ReleaseFast,
        });

        b.installArtifact(sample_exe);

        const run_step = b.addRunArtifact(sample_exe);
        run_step.step.dependOn(b.getInstallStep());

        const run_cmd = b.step("run", "run a sample executable");
        run_cmd.dependOn(&run_step.step);
    }
}

/// adds a single module and compile step containing
/// all included tests (based on specified options)
fn buildTests(b: *std.Build, lib_mod: *Module, deps: Dependencies) void {
    _ = b;
    _ = lib_mod;
    _ = deps;
}
// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const opts = BuildOpts{
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    };

    const deps = buildDeps(b, opts);
    const lib_mod = buildLibrary(b, deps, opts);

    // handle samples and testing if specified
    buildSamples(b, lib_mod, deps, opts);
    buildTests(b, lib_mod, deps);
}
