//! A pretty temporary implementation for
//! basic descriptor management in vulkan, manages it's own pool for now
const std = @import("std");

const vk = @import("vulkan");
const util = @import("../util.zig");
const common = @import("common_types.zig");

const api = @import("api.zig");

const Context = @import("../context.zig");

const Allocator = std.mem.Allocator;
const DeviceHandler = api.DeviceHandler;
const UniformBuffer = api.ComptimeUniformBuffer;
const CommandBuffer = api.CommandBuffer;
const AnyBuffer = api.BufInterface;
const Image = api.Image;

const log = std.log.scoped(.descriptor);

fn createDescriptorPool(pr_dev: *const vk.DeviceProxy) !vk.DescriptorPool {
    return try pr_dev.createDescriptorPool(&.{
        // NOTE: In the future, pools and sets will be managed separately :)
        .pool_size_count = 1,
        .max_sets = 1,
        .p_pool_sizes = util.asManyPtr(vk.DescriptorPoolSize, &.{
            .type = .uniform_buffer,
            .descriptor_count = 1,
        }),
    }, null);
}

pub const Config = struct {
    layout: DescriptorLayout,
    usage: common.DescriptorUsageInfo,
};

pub const DescriptorType = common.DescriptorType;

// flattened since buffers are the same regardless
// of whether they be uniform or storage
const BindingWriteInfo = union(enum) {
    Image: vk.DescriptorImageInfo,
    Buffer: vk.DescriptorBufferInfo,
};

/// ## Notes
/// The order you specify the bindings to the function
/// is the (0 indexed) order they be actually laid out
const Self = @This();

h_desc_set: vk.DescriptorSet,
pr_dev: *const vk.DeviceProxy,

layout: DescriptorLayout,

pub fn init(ctx: *const Context, config: Config) !Self {
    if (config.layout.layout == null) {
        log.err("Invalid descriptor layout (likely forgot to call resolve())", .{});
        return error.InvalidLayout;
    }

    const dev: *const DeviceHandler = ctx.env(.dev);
    var desc_pools = ctx.env(.desc);

    const desc_set = try desc_pools.reserve(config.usage, config.layout.layout.?);

    var descriptor = Self{
        .layout = config.layout,
        .pr_dev = &dev.pr_dev,
        .h_desc_set = desc_set,
    };
    errdefer descriptor.deinit();

    return descriptor;
}

pub const BindInfo = struct {
    bind_point: vk.PipelineBindPoint = .graphics,
};

/// formerly "bind" (renamed to avoid confusion with
/// binding concrete resources to descriptor slots)
pub fn use(
    self: *const Self,
    cmd_buf: *const CommandBuffer,
    layout: vk.PipelineLayout,
    info: BindInfo,
) void {
    self.pr_dev.cmdBindDescriptorSets(
        cmd_buf.h_cmd_buffer,
        info.bind_point,
        layout,
        0,
        1,
        &.{self.h_desc_set},
        0,
        null,
    );
}

pub fn deinit(self: *Self) void {//, ctx: *const Context) void {
    //FIXME: Can't pass context until lifecyle routines are integrated
    _ = self;

    //var desc_pool = ctx.env(.desc);
    // this may do nothing depending on usage
    //desc_pool.free(self.usage, self.h_desc_set);
    //self.layout.deinit();
}

pub fn bindUniformsNamed(self: *Self, name: []const u8, ubo: AnyBuffer) void {
    const loc = self.layout.named_bindings.get(name) orelse return;
    self.bindUniforms(loc, ubo);
}

pub fn bindSamplerNamed(self: *Self, name: []const u8, sampler: vk.Sampler, view: Image.View) void {
    const loc = self.layout.named_bindings.get(name) orelse return;
    self.bindSampler(loc, sampler, view);
}

pub fn bindImageNamed(self: *Self, name: []const u8, img: *const Image, view: Image.View) void {
    const loc = self.layout.named_bindings.get(name) orelse return;
    self.bindImage(loc, img, view);
}

pub fn bindBufferNamed(self: *Self, name: []const u8, buf: AnyBuffer) void {
    const loc = self.layout.named_bindings.get(name) orelse return;
    self.bindBuffer(loc, buf);
}

pub fn bindUniforms(self: *Self, index: usize, ubo: AnyBuffer) void {
    self.bindBase(index, .{.Uniform = ubo});
}

pub fn bindSampler(self: *Self, index: usize, sampler: vk.Sampler, view: Image.View) void {
    self.bindBase(index, .{.Sampler = .{
        .sampler = sampler,
        .view = view,
    }});
}

//TODO: Get rid of *img if i don't need it
pub fn bindImage(self: *Self, index: usize, img: *const Image, view: Image.View) void {
    self.bindBase(index, .{.Image = .{
        .img = img,
        .view = view,
    }});
}

pub fn bindBuffer(self: *Self, index: usize, buf: AnyBuffer) void {
    self.bindBase(index, .{.StorageBuffer = buf});
}

fn bindBase(self: *Self, index: usize, b: DescriptorBinding) void {
    const write = &self.layout.writes[index];
    write.* = vk.WriteDescriptorSet{
        .descriptor_type = undefined,

        .dst_binding = @intCast(index),
        .dst_array_element = 0,
        .descriptor_count = 1,
        .dst_set = self.h_desc_set,

        .p_buffer_info = undefined,
        .p_image_info = undefined,
        .p_texel_buffer_view = undefined,
    };

    var binding: BindingWriteInfo = undefined;

    switch (b) {
        .Sampler => |sampler| {
            binding = .{ .Image = vk.DescriptorImageInfo{
                .image_layout = .read_only_optimal,
                .image_view = sampler.view.h_view,
                .sampler = sampler.sampler,
            } };

            write.descriptor_type = .combined_image_sampler;
            write.p_image_info = &.{binding.Image};
        },
        .Image => |img| {
            binding = .{ .Image = vk.DescriptorImageInfo{
                .image_layout = .general,
                .image_view = img.view.h_view,
                .sampler = .null_handle,
            } };

            write.p_image_info = &.{binding.Image};
            write.descriptor_type = .storage_image;
        },
        else => {
            const buf: AnyBuffer, const dt: vk.DescriptorType = switch (b) {
                .Uniform => |buf| .{ buf, .uniform_buffer },
                .StorageBuffer => |buf| .{ buf, .storage_buffer },
                else => unreachable,
            };

            binding = .{ .Buffer = vk.DescriptorBufferInfo{
                .buffer = buf.handle,
                .offset = 0,
                .range = buf.size,
            } };

            write.descriptor_type = dt;

            write.p_buffer_info = &.{binding.Buffer};
        },
    }
}


/// Write descriptor values to the descriptor set.
/// -- This should happen anytime the descriptor's makeup changes
/// (i.e a new texture or buffer is needed)
/// Do note that just updating data of existing uniform or storage buffers
/// should just be done directly using the "setValue" function
pub fn update(self: *Self) void {
    self.pr_dev.updateDescriptorSets(
        @intCast(self.layout.writes.len),
        self.layout.writes.ptr,
        0,
        null,
    );
}

pub fn vkLayout(self: *const Self) vk.DescriptorSetLayout {
    // this has already been checked during initialization.
    return self.layout.layout orelse unreachable;
}

/// Formerly "update"
pub fn setValue(self: *Self, index: usize, data: anytype) !void {
    const binding = self.resolved_bindings[index];
    switch (binding.data) {
        .Uniform => |buf| try buf.setData(data),
        .StorageBuffer => |buf| try buf.setData(data),
        else => {
            log.err("Images may not be written from via descriptors", .{});
            return error.Unsupported;
        },
    }
}

const DescriptorBinding = union(DescriptorType) {
    Uniform: AnyBuffer,
    Sampler: struct {
        sampler: vk.Sampler,
        view: Image.View,
    },
    StorageBuffer: AnyBuffer,
    Image: struct {
        img: *const Image,
        view: Image.View,
    },
};

const debug = std.debug;

// Descriptor layouts done better
pub const DescriptorLayout = struct {
    const Specifier = struct { 
        u32, 
        []const u8, 
        DescriptorType, 
        vk.ShaderStageFlags, 

    };

    fn id(spec: Specifier) SpecifierID {
        return SpecifierID{
            .type = @intCast(spec.@"2".toIndex()),
            .stage_flags = spec.@"3",
        };
    }
    const SpecifierID = packed struct {
        type: u32,
        stage_flags: vk.ShaderStageFlags,
    };

    di: *const api.DeviceInterface,
    allocator: Allocator,

    specifiers: std.ArrayListUnmanaged(Specifier),
    named_bindings: std.StringArrayHashMapUnmanaged(usize),
    
    writes: []vk.WriteDescriptorSet,
    layout: ?vk.DescriptorSetLayout = null,
    size: usize,

    /// Screw you, just figure out how many descriptors you need before
    /// allocating shit all over the place.
    pub fn init(ctx: *const Context, allocator: Allocator, size: usize) !DescriptorLayout {
        var bindings_map = try std.StringArrayHashMapUnmanaged(usize).init(allocator, &.{}, &.{});
        errdefer bindings_map.deinit(allocator);

        const writes_buf = try allocator.alloc(vk.WriteDescriptorSet, size);
        errdefer allocator.free(writes_buf);

        var specifiers = try std.ArrayListUnmanaged(Specifier).initCapacity(allocator, size);
        errdefer specifiers.deinit(allocator);

        try bindings_map.ensureTotalCapacity(allocator, size);
        return DescriptorLayout{
            .di = ctx.env(.di),
            .allocator = allocator,

            .specifiers = specifiers,
            .named_bindings = bindings_map,

            .writes = writes_buf,
            .size = size,
        };
    }

    pub fn addDescriptor(self: *DescriptorLayout, spec: Specifier) void {
        debug.assert(self.specifiers.items.len + 1 < self.size);
        self.specifiers.appendAssumeCapacity(spec);
        self.named_bindings.putAssumeCapacity(spec.@"1", self.specifiers.items.len - 1);
    }

    pub fn addDescriptors(self: *DescriptorLayout, specs: []const Specifier) void {
        debug.assert(self.specifiers.items.len + specs.len < self.size);

        for (specs) |spec| {
            self.specifiers.insertAssumeCapacity(@intCast(spec.@"0"), spec);
            self.named_bindings.putAssumeCapacity(spec.@"1", self.specifiers.items.len - 1);
        }
    }

    pub fn resolve(self: *DescriptorLayout) !void {
        const layout_infos = try self.allocator.alloc(vk.DescriptorSetLayoutBinding, self.size);  
        defer self.allocator.free(layout_infos);

        for (self.specifiers.items, layout_infos) |spec, *layout_info| {
            layout_info.descriptor_count = 1;
            layout_info.descriptor_type = spec.@"2".toVkDescriptor();

            layout_info.binding = spec.@"0";
            layout_info.stage_flags = spec.@"3";
        }

        self.layout = try self.di.createDescriptorSetLayout(&.{
            .binding_count = @intCast(layout_infos.len),
            .p_bindings = layout_infos.ptr,
        }, null); 
    }

    pub fn deinit(self: *const DescriptorLayout) void {
        self.allocator.free(self.writes);
        self.specifiers.deinit(self.allocator);
        
        if (self.layout) |l| {
            self.di.destroyDescriptorSetLayout(l, null);
        }
    }
};

//TODO: Unfortunately any unit tests involving context-inditialized objects
//are impossible because the context explodes when you don't intialize it correctly
//(i.e without a window, since you shouldn't have unit tests spawn a gajillion windows if
//you can help it)

//NOTE: Example usage
//
//pub fn thing() void {
//    const ctx: Context = undefined;
//    const allocator: Allocator = undefined;
//
//    var layout = try DescriptorLayout.init();
//
//    try layout.addDescriptors(&.{
//        .{ 0, "Uniforms", .Uniform },
//        .{ 1, "MainTex", .Sampler },
//        .{ 2, "ComputeOutput", .Image },
//    });
//    try layout.resolve();
//
//    //NOTE: You give ownership to the descriptor when you
//    var desc = try Self.init(ctx, allocator, layout);
//    
//    // After consideration, I have elected to prefix this family of functions
//    // with "bind", as they are what associates a concrete resource
//    // with the descriptor "slot" persay. In the case of image-type descriptors,
//    // these functions are literally all that you need to associate a concrete 
//    // image with a descriptor slot, making them almost analogous with "glBindTexture" and such.
//    desc.bindUniformsNamed("Uniforms", some_ubo);
//    desc.bindSamplerNamed("MainTex", some_texture);
//    desc.bindBufferNamed("BuffyTheBuffer", some_buffer);
//    desc.bindImageNamed("ComputeOutput", some_storage_image);
//
//    desc.update();
//}
