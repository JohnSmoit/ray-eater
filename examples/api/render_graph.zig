//! Example usage of render graphs, for construction of various pipelines
const std = @import("std");
const ray = @import("ray");

const Context = ray.Context;
const PixelFormat = ray.PixelFormat;


// Obviously, don't use the raw page allocator for code that you don't
// want to suck
const allocator = std.heap.page_allocator;

/// Deferred rendering
/// with lighting pass
fn exampleDeferred() !void {
    const ctx = try Context.init(.{.Managed = .{
        .allocator = allocator,
    }});
    defer ctx.deinit(.{});
    
    // Probably should replace comptime strings with enum values
    // cuz they're more LSP friendly
    const graph = try ctx.env("render_graph");

    const g_buf = graph.addPass("gbuf", .graphics);

    // PixelFormats are predefined instances of packed structs...
    g_buf.addColorOutput("albedo", .{.format = PixelFormat.r8g8b8_srgb}, null);
    g_buf.addColorOutput("emissive", .{.format = PixelFormat.r10g11b11_ufloat_pack32}, null);
    g_buf.addColorOutput("normals", .{.format = PixelFormat.a2r10g10b10_unorm_pack32}, null);
    g_buf.setDepthOutput("depth", .{.format = ctx.env("device").getDepthStencilFormat()}, null);

    const lighting = graph.addPass("lighting", .graphics);
    lighting.addColorOutput("HDR", "emissive", .{}); // automatic format propogation
    lighting.addInput("albedo");
    lighting.addInput("emissive");
    lighting.addInput("normals");
    lighting.addInput("depth");
    lighting.setDepthInput("depth");
    
    // set the output resource for the graph to the main surface's current swapchain backbuffer
    graph.setDst(ctx.env("surface").getBackbuffer());
    
    // resolve everything (including the render graph)
    ctx.finalize(.{});
    
    const sphere_obj: *SceneObject = null; // replace with some scene object (likely done automatically from the scene)
    ctx.lit_queue.render(sphere_obj);
}


/// Example (speculative) raymarched pipeline for basic shape generation
fn basicRaymarch() !void {

}
