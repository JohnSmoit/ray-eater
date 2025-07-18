const std = @import("std");

const api = @import("ray").api;

const Context = api.Context;
const Swapchain = api.Swapchain;

pub fn main() !void {
    std.debug.print("COMPUTER SHADER NOW|n\n", .{});
}
