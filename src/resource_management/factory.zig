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
    comptime fac_config: Config,
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
        ) !*APIType {
            const ConfigType = @TypeOf(config);
            const EnvFields = crapi.ResolveEnv(APIType);
            const ErrorType = crapi.ComptimeEntry(APIType).init_errors;
            const InitFunc = *const fn (
                *APIType,
                *Context,
                *EnvFields,
                ConfigType,
            ) ErrorType!APIType;

            const reg_entry = self.ctx.registry.getEntry(common.typeId(APIType)) orelse
                return error.InvalidAPIType;

            const populated_env = EnvFields.populate(self.ctx.ctx_env);
            // nice and safe.
            const initFn: InitFunc = @ptrCast(@alignCast(reg_entry.initFn));

            try initFn(inst, self.ctx, populated_env, config);
            return inst;
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

            /// some management modes return different handle variants or just pointers.
            /// This depends on the handle variant of the particular type
            pub fn init(
                self: *Factory,
                comptime APIType: type, 
                config: crapi.ResolveConfigType(APIType),
            ) !crapi.ManagedReturnType(APIType) { 
            }

            pub fn initPreconfig(
                self: *Factory,
                comptime APIType: type, 
                comptime profile: crapi.ResolveConfigRegistry(APIType).Profiles,
                params: anytype,
            ) !crapi.ManagedReturnType(APIType) {
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
            }

            pub fn initPreconfig(
                self: *Factory,
                comptime APIType: type, 
                comptime profile: crapi.ResolveConfigRegistry(APIType).Profiles,
                allocator: std.mem.Allocator,
                params: anytype,
            ) !*APIType {
            }

            pub fn initInPlace(
                self: *Factory,
                comptime APIType: type, 
                inst: *APIType,
                config: crapi.ResolveConfigType(APIType),
            ) !void {
            }
            
            pub fn initInPlacePreconfig(
                self: *Factory,
                comptime APIType: type, 
                comptime profile: crapi.ResolveConfigRegistry(APIType).Profiles,
                inst: *APIType,
                params: anytype,
            ) !void {
            }
        },
    };
}

test "factory functionality" {
    const app = try Context.init(testing.allocator, .{});

    var managed_factory = app.getAPIFactory(.managed, .{});
    var unmanaged_factory = app.getAPIFactory(.unmanaged, .{});

    const jerry_face_image1 = try managed_factory.init(api.Image, .{
        .some_image_config = .yadda_yadda,
    });

    const jerry_face_image12 = try unmanaged_factory.init(
        api.Image,
        testing.allocator,
        .{
            .some_image_config = .yadda_yadda,
        },
    );

    var jerry_face_image121: api.Image = undefined;
    try unmanaged_factory.initInPlace( // this variant only exists on unmanaged thingies
        api.Image,
        &jerry_face_image121,
        .{
            .some_image_config = .yadda_yadda,
        },
    );

    const jerry_face_image2 = try managed_factory.initPreconfig(api.Image, .SomeProfileName, .{
        .extra_option = .yadda,
    });
}
