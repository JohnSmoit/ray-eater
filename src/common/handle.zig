const std = @import("std");
const common = @import("common.zig");

// const ct = common.ct;

const AnyPtr = common.AnyPtr;

pub const Config = struct {
    index_bits: usize = 32,
    gen_bits: usize = 32,

    partition_bit: ?usize = null,
};

fn PartitionIndexType(index_bits: usize, partition: usize) type {
    return if (partition == 0) 
        std.meta.Int(.unsigned, index_bits)
    else
        packed struct {
            lhs: std.meta.Int(.unsigned, partition),
            rhs: std.meta.Int(.unsigned, index_bits - partition),
        };
}


pub fn Handle(
    comptime T: type,
    comptime config: Config,
) type {
    const partition_bit = config.partition_bit orelse 0;

    if (config.index_bits > 64) 
        @compileError(
            "index_bits (" ++ 
            config.index_bits ++ 
            ") must be within the range of <=64");

    if (partition_bit > config.index_bits) 
        @compileError("index bit partition must lie within the range of index bits");

    const IndexType =  PartitionIndexType(config.index_bits, partition_bit);

    if (config.gen_bits == 0) {
        return packed struct {
            const Self = @This();
            const Type = T;

            pub fn Reified(err: type, getter: *const fn (*anyopaque, Self) err!*T) type {
                return packed struct {
                    h: Self,
                    p: *anyopaque,

                    pub fn get(self: @This()) err!*T {
                        return getter(self.p, self.h);
                    }

                    pub fn init(h: Self, mem: *anyopaque) @This() {
                        return .{
                            .h = h,
                            .p = mem,
                        };
                    }
                };
            } 

            index: IndexType,

        };
    }
    else {
        // gen is included only if we want a generation counter
        const GenType = std.meta.Int(.unsigned, config.gen_bits);

        return packed struct {
            const Type = T;
            const Self = @This();

            /// Uhh duplicate im lazy
            pub fn Reified(err: type, getter: *const fn (*anyopaque, Self) err!*T) type {
                return packed struct {
                    h: Self,
                    p: *anyopaque,

                    pub fn get(self: @This()) err!*T {
                        return getter(self.p, self.h);
                    }

                    pub fn init(h: Self, mem: *anyopaque) @This() {
                        return .{
                            .h = h,
                            .p = mem,
                        };
                    }
                };
            } 


            gen: GenType,
            index: IndexType,
        };
    }
}


pub const OpaqueHandle = packed struct {
};
