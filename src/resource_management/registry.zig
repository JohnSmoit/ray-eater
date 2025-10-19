//! Registry for all existing API types containg information about
//! how they should be handled by the resource manager/API handlers
//!
//!NOTE:
//! This is globally defined and not scoped to an application context
const std = @import("std");

// this is an example of how api functions should be signatured
// There are 2 possible signatures, one without an allocator,
// and the other with it. The expected signature is configured by
// How the entry is specified in the type registry at compile time.
// Due to the function pointery nature of this crap, error unions need to be explicitly specified
// For types that require ad-hoc initializatoin allocations,
// (This is usually I sign that I messed something up)
// pub fn exampleInit(
//     self: *Self,
//     ctx: *Context,
//     env: SomeEnvSubset,
//     config: Config,
// ) error{bitch}!Self {}

const common = @import("common");
const Context = @import("../context.zig");
const cfg = common.config;
const env = @import("../env.zig");

const Allocator = std.mem.Allocator;
const AnyPtr = common.AnyPtr;
const TypeId = common.TypeId;

const Self = @This();

pub const PfnAddRegistryEntries = *const fn () []EntryConfig;

pub const ManagementMode = enum {
    Unmanaged,
    Pooled,
    Transient,
    Streamed,
};

pub const EntryConfig = struct {
    // type for storing data
    State: type,

    // type for associating and operating on data
    Proxy: type,

    // error set for init functions (omit for anyerror)
    InitErrors: type = error{},

    // the type of the configuration struct (if any)
    ConfigType: type = struct {},
    // whether or not initialization depends on an allocator
    management: ManagementMode = .Pooled,

    initFn: *const anyopaque,
    deinitFn: *const anyopaque,
};

const ObjectPool = common.ObjectPool;


/// Comptime registry API
/// In comptime, the types themselves are the registries.
/// Hopefully, this doesn't slow compilation to a crawl...
/// The working of this registry API depends on a coherent
/// naming scheme for faster lookups
pub const ComptimeAPI = struct {
    pub fn ManagedResourceType(comptime mode: ManagementMode, comptime T: type) type {
        const PoolType = ObjectPool(T, .{});
        return switch (mode) {
            .Pooled, .Streamed => PoolType.ReifiedHandle,
            else => *T,
        };
    }

    // gets the config registry, cuz thats a generic
    fn ConfigRegistryFor(comptime T: type) type {
        return if (@hasDecl(T, "Registry"))
            @TypeOf(T.Registry)
        else
            @compileError("Invalid type " ++ @typeName(T) ++ " (missing config registry)");
    }

    /// Resolves the handle type from the API type as well as the management mode
    pub fn ManagedReturnType(comptime T: type) type {
        const registry = GetRegistry(T) orelse
            @compileError("Invalid type: " ++ @typeName(T) ++ " (missing type registry)");

        return registry.Proxy;
    }

    pub fn ProxyAPIMixin(comptime T: type) type {
        _ = T;
        return u32;
    }

    pub fn ResolveConfigRegistry(comptime ConfigType: type) ConfigRegistryFor(ConfigType) {
        return ConfigType.Registry;
    }

    pub fn ResolveConfigType(comptime APIType: type) type {
        return if (@hasDecl(APIType, "Config")) APIType.Config else struct {};
    }

    pub fn GetRegistry(comptime APIType: type) ?EntryConfig {
        if (!@hasDecl(APIType, "entry_config")) return null;
        return APIType.entry_config;
    }

    /// Given the type's API registry entry, returns the corresponding handle type
    /// which differs depending on the management mode.
    pub fn HandleFor(comptime T: type) type {
        const entry_config = GetRegistry(T) orelse
            @compileError("cannot create a proxy for: " ++ @typeName(T) ++ " (no entry config)");
        return ManagedResourceType(entry_config.management, T);
    }

    pub fn EnvFor(comptime T: type) type {
        return if (@hasDecl(T, "Env")) T.Env else env.Empty();
    }
};

// this returns the meta-information of the registry entry
// (underlying function types, unique type identifier)
pub fn RegistryEntryType(comptime config: EntryConfig) type {
    return struct {
        // remember, these functions should be remapped first arguments to the proxy
        pub const InitFnType = InitFnTemplate(config);
        pub const DeinitFnType = DeinitFnTemplate(config);
        pub const entry_id = common.typeId(config.State);
    };
}

/// NOTE: this could be a lot less branchy and stupid, but
/// that would come at the cost of @Type, which is not supported
/// by LSPs. I might redo this if it turns out this template doesn't
/// get directly touched by user code.
fn InitFnTemplate(comptime config: EntryConfig) type {
    const error_type = config.InitErrors orelse anyerror;
    if (config.config_type) |ct| {
        if (config.requires_alloc) {
            return *const fn (*config.State, *const Context, Allocator, ct) error_type!void;
        } else {
            return *const fn (*config.State, *const Context, ct) error_type!void;
        }
    } else {
        if (config.requires_alloc) {
            return *const fn (*config.State, *const Context, Allocator) error_type!void;
        } else {
            return *const fn (*config.State, *const Context) error_type!void;
        }
    }
}

fn DeinitFnTemplate(comptime config: EntryConfig) type {
    return if (config.requires_alloc)
        (*const fn (*config.State, Allocator) void)
    else
        (*const fn (*config.State) void);
}

pub const RegistryEntry = struct {
    type_id: TypeId,
    type_name: []const u8,
    size_bytes: usize,

    initFn: *const anyopaque,
    deinitFn: *const anyopaque,

    management: ManagementMode,
};

entries: std.ArrayList(RegistryEntry),
typeid_index: std.AutoHashMap(TypeId, *const RegistryEntry),

pub fn init(allocator: Allocator) !Self {
    return .{
        .entries = std.ArrayList(RegistryEntry).init(allocator),
        .typeid_index = std.AutoHashMap(TypeId, *const RegistryEntry).init(allocator),
    };
}

/// the type referenced by "T" must match the shape of
/// a configurable type as defined in the "CRAPI"
/// type specification
pub fn addEntry(
    self: *Self,
    comptime T: type,
) void {
    const entry_config = ComptimeAPI.GetRegistry(T) orelse
        @compileError("cannot create a registry entry for type: " ++ @typeName(T) ++ " (no entry config)");

    const entry = RegistryEntry{
        .initFn = entry_config.initFn,
        .deinitFn = entry_config.deinitFn,

        .type_id = common.typeId(entry_config.State),
        .type_name = @typeName(entry_config.State),
        .management = entry_config.management,
        .size_bytes = @sizeOf(entry_config.State),
    };

    // If the type registry fails to build, there is literally nothing to be done about it.
    // Probably shouldn't just panic tho :(
    self.entries.append(entry) catch
        @panic("Failed to build type registry due to an allocation error!");

    self.typeid_index.put(
        common.typeId(entry_config.State),
        &self.entries.items[self.entries.items.len - 1],
    ) catch
        @panic("Failed to build type registry due to being out of memory");
}

pub fn getEntry(
    self: *const Self,
    id: TypeId,
) ?*const RegistryEntry {
    return self.typeid_index.get(id);
}

pub const PredicateFn = *const fn (*const RegistryEntry) bool;
pub const Predicate = struct {
    pub fn ManagementModeIs(comptime mode: ManagementMode) PredicateFn {
        const Container = struct {
            pub fn predicate(entry: *const RegistryEntry) bool {
                return entry.management == mode;
            }
        };

        return Container.predicate;
    }

    pub fn TypeIdMatches(comptime id: TypeId) PredicateFn {
        const Container = struct {
            pub fn predicate(entry: *const RegistryEntry) bool {
                return entry.type_id == id;
            }
        };

        return Container.predicate;
    }
};

const debug = std.debug;

pub const Query = struct {
    const MAX_PREDICATES = 6;

    predicates: [MAX_PREDICATES]PredicateFn,
    num_predicates: u8,
    entries: []RegistryEntry,

    pub const Iterator = struct {
        entries: []const RegistryEntry,
        predicates: []PredicateFn,
        index: usize,

        fn matches(self: *Iterator, entry: *const RegistryEntry) bool {
            for (self.predicates) |p| {
                if (!p(entry)) return false;
            }

            return true;
        }

        pub fn next(self: *Iterator) ?*const RegistryEntry {
            while (self.index < self.entries.len and
                !self.matches(&self.entries[self.index])) : (self.index += 1)
            {}

            if (self.index < self.entries.len) {
                const tmp = &self.entries[self.index];
                self.index += 1;

                return tmp;
            } else {
                return null;
            }
        }
    };

    pub fn where(self: *Query, predicate: PredicateFn) *Query {
        debug.assert(self.num_predicates < MAX_PREDICATES);

        self.predicates[@intCast(self.num_predicates)] = predicate;
        self.num_predicates += 1;

        return self;
    }

    pub fn iterator(self: *Query) Iterator {
        return Iterator{
            .index = 0,
            .entries = self.entries,
            .predicates = self.predicates[0..self.num_predicates],
        };
    }

    pub fn first(self: *Query) ?*const RegistryEntry {
        var iter = self.iterator();
        return iter.next();
    }
};

/// begins an entry selection query
pub fn select(self: *Self) Query {
    return Query{
        .predicates = [_]PredicateFn{undefined} ** Query.MAX_PREDICATES,
        .num_predicates = 0,
        .entries = self.entries.items,
    };
}

pub fn deinit(self: *Self) void {
    self.entries.deinit();
}

const api = @import("../api/api.zig");
const testing = std.testing;

const NonexistentStruct = struct {};

test "api entries" {
    // try querying an existing entry
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var reg = try Self.init(arena.allocator());
    try api.initRegistry(&reg);

    var q1 = reg.select();
    const item = q1
        .where(Predicate.ManagementModeIs(.Pooled))
        .where(Predicate.TypeIdMatches(common.typeId(api.CommandBuffer.CommandBuffer)))
        .first();

    try testing.expect(item != null);
    try testing.expect(item.?.type_id == common.typeId(api.CommandBuffer.CommandBuffer));

    // try querying for something that doesn't exist
    var q2 = reg.select();
    const nonexistent = q2
        .where(Predicate.TypeIdMatches(common.typeId(NonexistentStruct)))
        .first();

    try testing.expect(nonexistent == null);
}
