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
    common: *Module,
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

    const common_mod = b.createModule(.{
        .optimize = opts.optimize,
        .target = opts.target,
        .root_source_file = b.path("src/common/common.zig"),
    });

    return .{
        .rshc = rshc_mod,
        .vulkan = vulkan_mod,
        .glfw = glfw_mod,
        .common = common_mod,
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
    lib_mod.addImport("common", deps.common);

    // Temporary for development
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
    desc: []const u8,
    path: []const u8 = "(no description)",

    // these get populated later
    mod: *Module = undefined,
    exe: *Compile = undefined,
};
var sample_files = [_]SampleEntry{
    .{
        .name = "basic-planes",
        .path = "basic_planes.zig",
        .desc = "basic showcase of bootstrapping vulkan up to 3d rendering",
    },
    .{
        .name = "compute-drawing",
        .path = "compute_drawing/main.zig",
        .desc = "drawing using compute shaders",
    },
    .{
        .name = "test-sample",
        .path = "test_sample.zig",
        .desc = "test to see if the sample build steps work correctly",
    },
    .{
        .name = "raymarch-fractals",
        .path = "raymarch_fractals/main.zig",
        .desc = "pick from a selection of raymarched fractals, all programmed within fragment shaders",
    },
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
            .optimize = opts.optimize orelse .ReleaseFast,
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

    for (sample_files) |entry| {
        b.installArtifact(entry.exe);

        const run_step = b.addRunArtifact(entry.exe);
        run_step.addArgs(b.args orelse &.{});

        run_step.step.dependOn(b.getInstallStep());

        const step_name = std.fmt.allocPrint(
            b.allocator,
            "run-{s}",
            .{entry.name},
        ) catch @panic("Achievement Get: How did we get here?");

        const run_cmd = b.step(step_name, entry.desc);
        run_cmd.dependOn(&run_step.step);
    }
}

/// adds a single module and compile step containing
/// all included tests (based on specified options)
fn buildTests(b: *Build, lib_mod: *Module, deps: Dependencies, opts: BuildOpts) void {
    const test_comp = b.addTest(.{
        .name = "unit_tests",
        .root_module = lib_mod,
        .target = opts.target,
    });

    const common_tests = b.addTest(.{
        .name = "common_unit_tests",
        .root_module = deps.common,
        .target = opts.target,
    });
    b.installArtifact(test_comp);
    b.installArtifact(common_tests);

    const test_step = b.addRunArtifact(test_comp);
    const common_test_step = b.addRunArtifact(common_tests);
    const test_cmd = b.step("test", "run all unit tests");
    
    test_cmd.dependOn(&test_step.step);
    test_cmd.dependOn(&common_test_step.step);
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
    buildTests(b, lib_mod, deps, opts);

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
