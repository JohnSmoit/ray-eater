//! Creating and destroying API types with a unified context,
//! configuration parameters, and common configurable interfaces.
const std = @import("std");

const Context = @import("../context.zig");
const Registry = @import("registry.zig");
const Self = @This();

const testing = std.testing;
const common = @import("common");
const cfg = common.config;
const api = @import("../api/api.zig");

const Config = struct {};

const FactoryVariant = enum { Managed, Unmanaged };


const crapi = Registry.ComptimeAPI;

pub fn APIFactory(
    comptime variant: FactoryVariant,
) type {

    // common set of functions
    const FactoryBase = struct {
        const FactoryBase = @This();
        ctx: *Context,

        pub fn createBase(
            self: *FactoryBase,
            comptime APIType: type,
            inst: *APIType,
            config: crapi.ResolveConfigType(APIType),
        ) !void {
            const entry_config = crapi.GetRegistry(APIType) orelse
                @compileError("Invalid API type: " ++ @typeName(APIType) ++ " (could not find registry config)");
            const EnvFields = crapi.EnvFor(APIType);
            const ConfigType = entry_config.ConfigType;
            const ErrorType = entry_config.InitErrors;
            const InitFunc = *const fn (
                *APIType,
                *Context,
                EnvFields,
                ConfigType,
            ) ErrorType!void;

            const reg_entry = self.ctx.registry.getEntry(common.typeId(APIType)) orelse
                return error.InvalidAPIType;

            const populated_env = EnvFields.populate(self.ctx.ctx_env);
            // nice and safe.
            const initFn: InitFunc = @ptrCast(@alignCast(reg_entry.initFn));

            try initFn(inst, self.ctx, populated_env, config);
        }

    

        /// Used for lifecycle deinits, users can just directly call
        /// deinit for the low-level API
        pub fn deinitBase() void {
        }
    };

    return switch(variant) {
        .Managed => struct {
            const Factory = @This();

            base: FactoryBase,

            fn allocManaged(
                self: *Factory, 
                comptime APIType: type, 
            ) !std.meta.Tuple(&.{
                *APIType, 
                crapi.ManagedReturnType(APIType)}
            ) {
                const ProxyType = crapi.ManagedReturnType(APIType);
                const entry_config = crapi.GetRegistry(APIType) orelse 
                    @compileError("Invalid registry");

                var ptr: *APIType = undefined;
                var proxy: ProxyType = undefined;

                switch (entry_config.management) {
                    //HACK: Technically, unmanaged types shouldn't
                    //be creatable from a managed factory
                    //For now, I just use the context allocator
                    .Unmanaged => {
                        ptr = try self.base.ctx.allocator.create(APIType);
                        proxy = .{.handle = ptr};
                    },
                    .Transient => {
                        ptr = try self.base.ctx.resources.createTransient(APIType);
                        proxy = .{.handle = ptr};
                    },
                    //TODO: Streamed allocations need an actual system
                    .Pooled, .Streamed => {
                        const handle = 
                            try self.base.ctx.resources.reservePooledByType(APIType);

                        ptr = handle.getAssumeValid();
                        proxy = .{.handle = handle};
                    },
                }

                return .{ptr, proxy};
            }

            /// some management modes return different handle variants or just pointers.
            /// This depends on the handle variant of the particular type
            pub fn create(
                self: *Factory,
                comptime APIType: type, 
                config: crapi.ResolveConfigType(APIType),
            ) !crapi.ManagedReturnType(APIType) { 
                const ptr, const h = try self.allocManaged(APIType);
                std.debug.print("Type of config: {s}\n", .{@typeName(@TypeOf(config))});
                try self.base.createBase(APIType, ptr, config);

                return h;
            }

            /// Creates a new API type with a pre-populated configuration value.
            /// Since, some vulkan objects can be heavy on parameterization.
            pub fn createPreconfig(
                self: *Factory,
                comptime APIType: type, 
                comptime profile: crapi.ResolveConfigRegistry(APIType).Profiles,
                params: anytype,
            ) !crapi.ManagedReturnType(APIType) {
                _ = self;
                _ = profile;
                _ = params;
            }
        },
        .Unmanaged => struct {
            const Factory = @This();

            base: FactoryBase,

            pub fn init(
                self: *Factory,
                comptime APIType: type, 
                allocator: std.mem.Allocator,
                config: crapi.ResolveConfigType(APIType),
            ) !*APIType {
                _ = self;
                _ = allocator;
                _ = config;
            }

            pub fn initPreconfig(
                self: *Factory,
                comptime APIType: type, 
                comptime profile: crapi.ResolveConfigRegistry(APIType).Profiles,
                allocator: std.mem.Allocator,
                params: anytype,
            ) !*APIType {
                _ = self;
                _ = profile;
                _ = allocator;
                _ = params;
            }

            pub fn initInPlace(
                self: *Factory,
                comptime APIType: type, 
                inst: *APIType,
                config: crapi.ResolveConfigType(APIType),
            ) !void {
                _ = self;
                _ = inst;
                _ = config;
            }
            
            pub fn initInPlacePreconfig(
                self: *Factory,
                comptime APIType: type, 
                comptime profile: crapi.ResolveConfigRegistry(APIType).Profiles,
                inst: *APIType,
                params: anytype,
            ) !void {
                _ = self;
                _ = profile;
                _ = inst;
                _ = params;
            }
        },
    };
}

const CommandBuffer = api.CommandBuffer.CommandBuffer;

test "factory functionality" {
    var factory_shit: APIFactory(.Managed) = undefined;

    _ = try factory_shit.create(CommandBuffer, .{.one_shot = true});
}
