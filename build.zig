const std = @import("std");

const Build = std.Build;
const Module = Build.Module;
const Compile = Build.Step.Compile;
const ResolvedTarget = Build.ResolvedTarget;
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
fn buildDeps(b: *Build, opts: BuildOpts) Dependencies {
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
    b: *Build,
    deps: Dependencies,
    opts: BuildOpts,
) struct { *Module, *Compile } {
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

    return .{ lib_mod, lib };
}

const SampleEntry = struct {
    name: []const u8,
    path: []const u8,

    // these get populated later
    mod: *Module = undefined,
    exe: *Compile = undefined,
};
var sample_files = [_]SampleEntry{
    .{ .name = "basic_planes", .path = "basic_planes.zig" },
    .{ .name = "compute_drawing", .path = "compute_drawing/main.zig" },
    .{ .name = "test_sample", .path = "test_sample.zig" },
};

fn populateSampleModules(
    b: *Build,
    lib_mod: *Module,
    deps: Dependencies,
    opts: BuildOpts,
) void {
    const sample_commons = b.createModule(.{
        .root_source_file = b.path("samples/common/helpers.zig"),
        .optimize = opts.optimize,
        .target = opts.target,
    });

    sample_commons.addImport("ray", lib_mod);
    sample_commons.addImport("glfw", deps.glfw);
    sample_commons.addImport("vulkan", deps.vulkan);

    for (&sample_files) |*f| {
        const sample_mod = b.createModule(.{
            .root_source_file = b.path(b.pathJoin(&.{
                "samples",
                f.path,
            })),
            .optimize = opts.optimize,
            .target = opts.target,
        });

        sample_mod.addImport("ray", lib_mod);
        sample_mod.addImport("glfw", deps.glfw);
        sample_mod.addImport("vulkan", deps.vulkan);
        sample_mod.addImport("helpers", sample_commons);

        const sample_exe = b.addExecutable(.{
            .name = f.name,
            .root_module = sample_mod,
        });

        f.mod = sample_mod;
        f.exe = sample_exe;
    }
}

/// build sample applications which demonstrate the usage
/// and features of the library
fn buildSamples(
    b: *Build,
    lib_mod: *Module,
    deps: Dependencies,
    opts: BuildOpts,
) void {
    populateSampleModules(b, lib_mod, deps, opts);

    const build_sample = b.option(
        []const u8,
        "sample",
        "specify sample to build and run",
    );
    if (build_sample) |sample_name| {
        var entry: ?*SampleEntry = null;

        for (&sample_files) |*f| {
            if (std.mem.order(u8, sample_name, f.name) == .eq) {
                entry = f;
                break;
            }
        }

        if (entry == null) return;

        b.installArtifact(entry.?.exe);

        const run_step = b.addRunArtifact(entry.?.exe);
        run_step.step.dependOn(b.getInstallStep());

        const run_cmd = b.step("run", "run a sample executable");
        run_cmd.dependOn(&run_step.step);
    }
}

/// adds a single module and compile step containing
/// all included tests (based on specified options)
fn buildTests(b: *Build, lib_mod: *Module, deps: Dependencies) void {
    _ = b;
    _ = lib_mod;
    _ = deps;
}
// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *Build) void {
    const opts = BuildOpts{
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    };

    const deps = buildDeps(b, opts);
    const lib_mod, const lib_exe = buildLibrary(b, deps, opts);

    // handle samples and testing if specified
    buildSamples(b, lib_mod, deps, opts);
    buildTests(b, lib_mod, deps);

    // zls-friendly check step
    // (which made all the rest of the code way grosser)
    // ... sigh
    const check_step = b.step(
        "check",
        "test project build without installing artifacts",
    );

    check_step.dependOn(&lib_exe.step);
    for (&sample_files) |f| {
        check_step.dependOn(&f.exe.step);
    }
}
