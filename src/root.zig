//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const vk = @import("vulkan");
// bare bones test to see if I package managed vulkan correctly ;(
pub fn testInstance() !void {
    const poop = vk.makeApiVersion(1, 2, 1, 2);
    std.debug.print("Test version packed: {d}\n", .{@as(@typeInfo(vk.Version).@"struct".backing_integer.?, @bitCast(poop))});
}
