const std = @import("std");
const ray = @import("ray");
const glfw = @import("glfw");
const helpers = @import("common/helpers.zig");

const api = ray.api;

const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const Allocator = std.mem.Allocator;

const Context = ray.Context;
const Swapchain = api.Swapchain;
const FrameBuffer = api.FrameBuffer;
const GraphicsPipeline = api.GraphicsPipeline;
const RenderPass = api.RenderPass;
const FixedFunctionState = api.FixedFunctionState;
const Descriptor = api.Descriptor;
const DescriptorBinding = api.ResolvedDescriptorBinding;

const log = std.log.scoped(.application);

const GraphicsState = struct {
    descriptor: Descriptor,
    renderpass: RenderPass,
    framebuffers: FrameBuffer,
    pipeline: GraphicsPipeline,
};

const SampleState = struct {
    ctx: *Context = undefined,
    swapchain: Swapchain = undefined,
    window: glfw.Window = undefined,
    allocator: Allocator,

    graphics: GraphicsState = undefined,

    pub fn createContext(self: *SampleState) !void {
        self.window = try helpers.makeBasicWindow(900, 600, "BAD APPLE >:}");
        self.ctx = try Context.init(self.allocator, .{
            .inst_extensions = helpers.glfwInstanceExtensions(),
            .loader = glfw.glfwGetInstanceProcAddress,
            .window = &self.window,
        });
    }

    pub fn createSwapchain(self: *SampleState) !void {
        self.swapchain = try Swapchain.init(self.ctx, self.allocator, .{
            .requested_extent = helpers.windowExtent(&self.window),
            .requested_present_mode = .mailbox_khr,
            .requested_format = .{
                .color_space = .srgb_nonlinear_khr,
                .format = .r8g8b8a8_srgb,
            },
        });
    }

    pub fn createGraphicsPipelines(self: *SampleState) !void {
        const desc_bindings = [_]DescriptorBinding{.{}};

        self.graphics.descriptor = try Descriptor.init(self.ctx, self.allocator, .{
            .bindings = desc_bindings[0..],
        });
        const fixed_functions = FixedFunctionState{};
        //TODO: Rename this function
        try fixed_functions.init_self(self.ctx, .{
        });
        defer fixed_functions.deinit();

        const attachments = [_]RenderPass.ConfigEntry{.{
            .attachment = .{
                .format = .r8g8b8a8_srgb,
                .initial_layout = .undefined,
                .final_layout = .color_attachment_optimal,
                .load_op = .clear,
                .store_op = .store,
                .stencil_load_op = .dont_care,
                .stencil_store_op = .dont_care,
            },
            .tipo = .Color,
        }};
        self.graphics.renderpass = try RenderPass.initAlloc(self.ctx, self.allocator, attachments[0..]);

        self.graphics.framebuffers = try FrameBuffer.initAlloc(self.ctx, self.allocator, .{
            .image_views = self.swapchain.images,
            .extent = helpers.windowExtent(&self.window),
            .renderpass = &self.graphics.renderpass,
        });

        self.graphics.pipeline = try GraphicsPipeline.init(self.ctx, .{
            .renderpass = &self.graphics.renderpass,
            .fixed_functions = &fixed_functions,
            .shader_stages = undefined,
        }, self.allocator);  
    }

    pub fn active(self: *const SampleState) bool {
        return !self.window.shouldClose();
    }

    // intercepts errors and logs them
    pub fn update(self: *SampleState) void {
        glfw.pollEvents();
        _ = self;
    }

    pub fn deinit(self: *SampleState) void {
        self.swapchain.deinit();
        self.ctx.deinit();
        self.window.destroy();
    }
};

pub fn main() !void {
    const mem = try std.heap.page_allocator.alloc(u8, 1_000_024);
    defer std.heap.page_allocator.free(mem);

    var buf_alloc = FixedBufferAllocator.init(mem);
    var state: SampleState = .{
        .allocator = buf_alloc.allocator(),
    };

    try state.createContext();
    try state.createSwapchain();
    state.window.show();

    while (state.active()) {
        state.update();
    }

    state.deinit();
    log.info("You Win!", .{});
}
