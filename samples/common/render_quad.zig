const std = @import("std");
const ray = @import("ray");
const api = ray.api;

const Allocator = std.mem.Allocator;

const Self = @This();

const Context = ray.Context;

const Descriptor = api.Descriptor;
const GraphicsPipeline = api.GraphicsPipeline;
const FixedFunctionState = api.FixedFunctionState;
const ShaderModule = api.ShaderModule;
const RenderPass = api.RenderPass;
const CommandBuffer = api.CommandBuffer;
const DeviceHandler = api.DeviceHandler;
const FrameBuffer = api.FrameBuffer;

const Swapchain = api.Swapchain;

pipeline: GraphicsPipeline = undefined,
renderpass: RenderPass = undefined,
dev: *const DeviceHandler = undefined,
swapchain: *const Swapchain = undefined,
desc: ?*const Descriptor = null,

const hardcoded_vert_src: []const u8 =
    \\ #version 450
    \\ vec2 verts[4] = vec2[](
    \\     vec2(-1.0, -1.0),
    \\     vec2( 1.0, -1.0),
    \\     vec2( 1.0,  1.0),
    \\     vec2(-1.0,  1.0)
    \\ ); 
    \\ vec2 uvs[4] = vec2[](
    \\     vec2(0.0, 0.0),
    \\     vec2(1.0, 0.0),
    \\     vec2(1.0, 1.0),
    \\     vec2(0.0, 1.0)
    \\);
    \\ uint ind[6] = uint[](
    \\     0, 1, 2, 0, 2, 3
    \\);
    \\ layout(location = 0) out vec2 texCoord;
    \\
    \\ void main() {
    \\     uint index = ind[gl_VertexIndex];
    \\     gl_Position = vec4(verts[index], 0.0, 1.0);
    \\     texCoord = uvs[index];
    \\ }
;

pub const Config = struct {
    // null if fragment shader has no referenced data
    // fragment descriptors are also combined with vertex descriptors
    frag_descriptors: ?*const Descriptor = null,
    frag_shader: *const ShaderModule,
    swapchain: *const Swapchain,
};

pub fn initSelf(self: *Self, ctx: *const Context, allocator: Allocator, config: Config) !void {
    const vert_shader = try ShaderModule.initFromSrc(
        ctx,
        allocator,
        hardcoded_vert_src,
        .Vertex,
    );
    defer vert_shader.deinit();

    const shaders: []const ShaderModule = &.{
        vert_shader,
        config.frag_shader.*,
    };

    var fixed_functions_config = FixedFunctionState{};
    fixed_functions_config.init_self(ctx, &.{
        .dynamic_states = &.{
            .viewport,
            .scissor,
        },
        .viewport = .{ .Swapchain = config.swapchain },
        .descriptors = if (config.frag_descriptors) |fd| &.{
            fd.h_desc_layout,
        } else &.{},
    });
    defer fixed_functions_config.deinit();

    self.renderpass = try api.RenderPass.initAlloc(ctx, allocator, &.{.{
        .attachment = .{
            .initial_layout = .undefined,
            .final_layout = .present_src_khr,
            .format = .r8g8b8a8_srgb,

            .load_op = .clear,
            .store_op = .store,

            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .samples = .{ .@"1_bit" = true },
        },
        .tipo = .Color,
    }});

    self.pipeline = try GraphicsPipeline.init(ctx, .{
        .fixed_functions = &fixed_functions_config,
        .renderpass = &self.renderpass,
        .shader_stages = shaders,
    }, allocator);

    self.dev = ctx.env(.dev);
    self.swapchain = config.swapchain;
    self.desc = config.frag_descriptors;
}

pub fn drawOneShot(self: *const Self, cmd_buf: *const CommandBuffer, framebuffer: *const FrameBuffer) void {
    self.pipeline.bind(cmd_buf);
    const image_index = self.swapchain.image_index;
    self.renderpass.begin(cmd_buf, framebuffer, image_index);

    if (self.desc) |d| {
        d.bind(cmd_buf, self.pipeline.h_pipeline_layout);
    }

    self.dev.draw(cmd_buf, 6, 1, 0, 0);
    self.renderpass.end(cmd_buf);
}

pub fn deinit(self: *Self) void {
    self.pipeline.deinit();
    self.renderpass.deinit();
}
