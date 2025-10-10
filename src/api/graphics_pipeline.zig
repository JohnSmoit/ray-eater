const std = @import("std");
const vk = @import("vulkan");
const base = @import("base.zig");
const util = @import("common").util;
const shader = @import("shader.zig");

const Allocator = std.mem.Allocator;

const Context = @import("../context.zig");
const DeviceHandler = base.DeviceHandler;
const Swapchain = @import("swapchain.zig");
const RenderPass = @import("renderpass.zig");
const CommandBuffer = @import("command_buffer.zig");

const Self = @This();

pub const FixedFunctionState = struct {
    /// ## Please note that for now, the following pipeline stages are hardcoded:
    /// * Rasterizer State
    /// * Input Assembler
    /// * Multisampler state
    /// * Color blending state
    /// ## Most other states will support limited configuration for the moment..
    ///
    /// Deez nuts must be enabled
    pub const Config = struct {
        dynamic_states: []const vk.DynamicState = &.{},
        viewport: union(enum) {
            Swapchain: *const Swapchain, // create viewport from swapchain
            Direct: struct { // specify fixed function viewport directly
                viewport: vk.Viewport,
                scissor: vk.Rect2D,
            },
        },
        vertex_binding: ?vk.VertexInputBindingDescription = null,
        vertex_attribs: []const vk.VertexInputAttributeDescription = &.{},
        descriptors: []const vk.DescriptorSetLayout,
        deez_nuts: bool = true,
    };

    // NOTE: This pipeline layout field has more to do with uniforms and by extension descriptor sets,
    // so putting it here isn't really gonna work
    // FIX: UUUUU WAIIII is this here it should be made in the pIPLEINE
    pipeline_layout_info: vk.PipelineLayoutCreateInfo = undefined,

    // fixed function pipeline state info
    // -- to be passed to the actual graphics pipeline
    dynamic_states: vk.PipelineDynamicStateCreateInfo = undefined,
    vertex_input: vk.PipelineVertexInputStateCreateInfo = undefined,
    input_assembly: vk.PipelineInputAssemblyStateCreateInfo = undefined,
    viewport: vk.Viewport = undefined,
    scissor: vk.Rect2D = undefined,
    viewport_state: vk.PipelineViewportStateCreateInfo = undefined,
    rasterizer_state: vk.PipelineRasterizationStateCreateInfo = undefined,
    multisampling_state: vk.PipelineMultisampleStateCreateInfo = undefined,
    blend_attachment: vk.PipelineColorBlendAttachmentState = undefined,
    color_blending_state: vk.PipelineColorBlendStateCreateInfo = undefined,

    pr_dev: *const vk.DeviceProxy = undefined,

    pub fn init_self(self: *FixedFunctionState, ctx: *const Context, config: *const Config) void {
        if (!config.deez_nuts) @panic("Deez nuts must explicitly be true!!!!!!");

        self.pr_dev = ctx.env(.di);

        const dynamic_states = config.dynamic_states;

        self.dynamic_states = vk.PipelineDynamicStateCreateInfo{
            .dynamic_state_count = @intCast(dynamic_states.len),
            .p_dynamic_states = dynamic_states.ptr,
        };

        self.vertex_input = vk.PipelineVertexInputStateCreateInfo{
            .vertex_binding_description_count = if (config.vertex_binding != null) 1 else 0,
            .p_vertex_binding_descriptions = if (config.vertex_binding) |*vb| util.asManyPtr(
                vk.VertexInputBindingDescription,
                vb,
            ) else null,
            .vertex_attribute_description_count = @intCast(config.vertex_attribs.len),
            .p_vertex_attribute_descriptions = config.vertex_attribs.ptr,
        };

        self.input_assembly = vk.PipelineInputAssemblyStateCreateInfo{
            .topology = .triangle_list,
            .primitive_restart_enable = vk.FALSE,
        };

        self.viewport, self.scissor = switch (config.viewport) {
            .Direct => |val| .{ val.viewport, val.scissor },
            .Swapchain => |swapchain| .{
                vk.Viewport{
                    .x = 0,
                    .y = 0,
                    .width = @floatFromInt(swapchain.extent.width),
                    .height = @floatFromInt(swapchain.extent.height),
                    .min_depth = 0.0,
                    .max_depth = 1.0,
                },
                vk.Rect2D{
                    .offset = .{ .x = 0, .y = 0 },
                    .extent = swapchain.extent,
                },
            },
        };

        self.viewport_state = vk.PipelineViewportStateCreateInfo{
            .viewport_count = 1,
            .scissor_count = 1,
            .p_scissors = util.asManyPtr(vk.Rect2D, &self.scissor),
            .p_viewports = util.asManyPtr(vk.Viewport, &self.viewport),
        };

        // This is one chonky boi
        self.rasterizer_state = vk.PipelineRasterizationStateCreateInfo{

            // whether to discard fragments that fall beyond the rasterizer's clipping planes or to clamp them
            // to the boundaries
            .depth_clamp_enable = vk.FALSE,

            // whether or not to discard geometry before rasterizing
            // (generally don't unless you don't want to render anything
            .rasterizer_discard_enable = vk.FALSE,

            // how to generate fragments for rasterized polygons,
            // for example, you can have them generated as filled shapes, or along edge lines
            // for a wireframed look
            .polygon_mode = .fill,

            // how fat to make the lines generated in line-based polygon modes
            .line_width = 1.0,

            // how to handle face culling, as generally one does not render both the front and back faces
            // of a given polygon. the front_face parameter determines the winding order used to deterimine
            // which side of a polygon is front and back.
            // NOTE: Reversing some of these is probably a good idea if we wanted an inverted shape, like
            // for a cubemapped skybox!
            .cull_mode = .{
                .back_bit = true,
            },
            .front_face = .clockwise,

            // whether or not to bias fragment depth values
            // not really sure what this is used for except for a vague notion
            // of something to do with shadow passes
            .depth_bias_enable = vk.FALSE,
            .depth_bias_constant_factor = 0,
            .depth_bias_clamp = 0,
            .depth_bias_slope_factor = 0,
        };

        // for now, we'll be disabling multisampling, but good to note for the future
        self.multisampling_state = vk.PipelineMultisampleStateCreateInfo{
            .sample_shading_enable = vk.FALSE,
            .rasterization_samples = .{
                // starting to see the downsides of prefix erasure here lmao
                .@"1_bit" = true,
            },
            .min_sample_shading = 1.0,
            .alpha_to_coverage_enable = vk.FALSE,
            .alpha_to_one_enable = vk.FALSE,
        };

        // TODO: Depth testing since a depth buffer will be essential in most ray based rendering operations

        // color blending information
        self.blend_attachment = vk.PipelineColorBlendAttachmentState{
            .color_write_mask = .{
                .r_bit = true,
                .g_bit = true,
                .b_bit = true,
                .a_bit = true,
            },
            // We basically don't do color blending or alpha blending at all here
            .blend_enable = vk.FALSE,

            // these parameters are how we configure the how the source (i.e framebuffer)
            // and destination (i.e fragment shader output) color values get combined into the final
            // framebuffer output. Color components and alpha components are specified separately
            .src_color_blend_factor = .one,
            .dst_color_blend_factor = .zero,
            .color_blend_op = .add,
            .src_alpha_blend_factor = .one,
            .dst_alpha_blend_factor = .zero,
            .alpha_blend_op = .add,
        };

        self.color_blending_state = vk.PipelineColorBlendStateCreateInfo{
            // whether or not to blend via a bitwise logical operation,
            // only do this if you do NOT want to specify blending via a color attachment
            // as I have above..
            .logic_op_enable = vk.FALSE,
            .logic_op = .copy,

            // otherwise, just specify color attachments like so
            .attachment_count = 1,
            .p_attachments = util.asManyPtr(
                vk.PipelineColorBlendAttachmentState,
                &self.blend_attachment,
            ),
            .blend_constants = .{ 0, 0, 0, 0 },
        };

        self.pipeline_layout_info = vk.PipelineLayoutCreateInfo{
            .set_layout_count = @intCast(config.descriptors.len),
            .p_set_layouts = config.descriptors.ptr,
            .push_constant_range_count = 0,
            .p_push_constant_ranges = null,
        };

        log.debug("Successfully initialized fixed function state!", .{});
    }

    pub fn deinit(self: *const FixedFunctionState) void {
        log.debug("Destroyed fixed function state", .{});

        _ = self;
    }
};

pub const PipelineConfig = struct {
    renderpass: *const RenderPass,
    fixed_functions: *const FixedFunctionState,
    shader_stages: []const shader.Module,
};

pub const log = std.log.scoped(.graphics_pipeline);

h_pipeline: vk.Pipeline = .null_handle,
h_pipeline_layout: vk.PipelineLayout = .null_handle,
pr_dev: *const vk.DeviceProxy,

viewport_info: vk.Viewport,
scissor_info: vk.Rect2D,

pub fn init(ctx: *const Context, config: PipelineConfig, allocator: Allocator) !Self {
    const dev: *const DeviceHandler = ctx.env(.dev);
    const pipeline_layout = dev.pr_dev.createPipelineLayout(
        &config.fixed_functions.pipeline_layout_info,
        null,
    ) catch |err| {
        log.err("Failed to create pipeline layout: {!}", .{err});
        return err;
    };

    var shader_stages = try allocator.alloc(
        vk.PipelineShaderStageCreateInfo,
        config.shader_stages.len,
    );
    defer allocator.free(shader_stages);

    for (config.shader_stages, 0..) |*stage, index| {
        shader_stages[index] = stage.pipeline_info;
    }

    var pipeline: vk.Pipeline = undefined;

    //NOTE: Mario vv

    // This is hardcoded mainly for demonstration purposes
    const depth_stencil = vk.PipelineDepthStencilStateCreateInfo{
        .depth_test_enable = vk.TRUE,
        .depth_write_enable = vk.TRUE,
        .depth_compare_op = .less,

        // depth ranges to discard fragments (not included)
        .depth_bounds_test_enable = vk.FALSE,
        .min_depth_bounds = 0.0,
        .max_depth_bounds = 1.0,

        // whether or not to also do stencil testing (not included)
        .stencil_test_enable = vk.FALSE,
        .front = undefined,
        .back = undefined,
    };

    _ = dev.pr_dev.createGraphicsPipelines(
        .null_handle,
        1,
        util.asManyPtr(
            vk.GraphicsPipelineCreateInfo,
            &.{
                // most of this stuff is either fixed function configuration
                // or renderpass with a bit of shader stages mixed in
                .stage_count = @intCast(config.shader_stages.len),
                .p_stages = shader_stages.ptr,
                .p_vertex_input_state = &config.fixed_functions.vertex_input,
                .p_input_assembly_state = &config.fixed_functions.input_assembly,
                .p_viewport_state = &config.fixed_functions.viewport_state,
                .p_rasterization_state = &config.fixed_functions.rasterizer_state,
                .p_multisample_state = &config.fixed_functions.multisampling_state,
                .p_depth_stencil_state = &depth_stencil,
                .p_color_blend_state = &config.fixed_functions.color_blending_state,
                .p_dynamic_state = &config.fixed_functions.dynamic_states,
                .layout = pipeline_layout,
                .render_pass = config.renderpass.h_rp,
                .subpass = 0,
                .base_pipeline_handle = .null_handle,
                .base_pipeline_index = -1,
            },
        ),
        null,
        // Disgusting
        @constCast(util.asManyPtr(vk.Pipeline, &pipeline)),
    ) catch |err| {
        log.err("Failed to initialize graphics pipeline: {!}", .{err});
        return err;
    };
    log.debug("Successfully initialized the graphics pipeline", .{});

    return .{
        .h_pipeline = pipeline,
        .h_pipeline_layout = pipeline_layout,
        .pr_dev = &dev.pr_dev,
        .viewport_info = config.fixed_functions.viewport,
        .scissor_info = config.fixed_functions.scissor,
    };
}

pub fn deinit(self: *const Self) void {
    self.pr_dev.destroyPipeline(self.h_pipeline, null);
    self.pr_dev.destroyPipelineLayout(self.h_pipeline_layout, null);

    log.debug("Successfully destroyed the graphics pipeline", .{});
}

pub fn bind(self: *const Self, cmd_buf: *const CommandBuffer) void {
    self.pr_dev.cmdBindPipeline(cmd_buf.h_cmd_buffer, .graphics, self.h_pipeline);
    self.pr_dev.cmdSetViewport(cmd_buf.h_cmd_buffer, 0, 1, util.asManyPtr(vk.Viewport, &self.viewport_info));
    self.pr_dev.cmdSetScissor(cmd_buf.h_cmd_buffer, 0, 1, util.asManyPtr(vk.Rect2D, &self.scissor_info));
}
