//! Registry for all existing API types containg information about
//! how they should be handled by the resource manager/API handlers
//!
//!NOTE:
//! This is globally defined and not scoped to an application context
const std = @import("std");

const common = @import("common");
const Context = @import("../context.zig");

const Allocator = std.mem.Allocator;
const AnyPtr = common.AnyPtr;
const TypeId = common.TypeId;

const Self = @This();

pub const EntryConfig = struct {
    // type for storing data
    state: type,

    // type for associating and operating on data
    proxy: type,

    // error set for init functions (omit for anyerror)
    init_errors: ?type,

    // the type of the configuration struct (if any)
    config_type: ?type = null,
    // whether or not initialization depends on an allocator
    requires_alloc: bool = false,
    management: ManagementMode = .Pooled,
};

// this returns the meta-information of the registry entry
// (underlying function types, unique type identifier)
pub fn RegistryEntryType(comptime config: EntryConfig) type {
    return struct {
        // remember, these functions should be remapped first arguments to the proxy
        pub const InitFnType = InitFnTemplate(config);
        pub const DeinitFnType = DeinitFnTemplate(config);
        pub const entry_id = common.typeId(config.state);
    };
}

/// NOTE: this could be a lot less branchy and stupid, but
/// that would come at the cost of @Type, which is not supported
/// by LSPs. I might redo this if it turns out this template doesn't
/// get directly touched by user code.
fn InitFnTemplate(comptime config: EntryConfig) type {
    const error_type = config.init_errors orelse anyerror;
    if (config.config_type) |ct| {
        if (config.requires_alloc) {
            return *const fn (*config.state, *const Context, Allocator, ct) error_type!void;
        } else {
            return *const fn (*config.state, *const Context, ct) error_type!void;
        }
    } else {
        if (config.requires_alloc) {
            return *const fn (*config.state, *const Context, Allocator) error_type!void;
        } else {
            return *const fn (*config.state, *const Context) error_type!void;
        }
    }
}

fn DeinitFnTemplate(comptime config: EntryConfig) type {
    return if (config.requires_alloc)
        (*const fn (*config.state, Allocator) void)
    else
        (*const fn (*config.state) void);
}

pub const RegistryEntry = struct {
    type_id: TypeId,
    type_name: []const u8,

    initFn: AnyPtr,
    deinitFn: AnyPtr,

    management: ManagementMode,
};

pub const ManagementMode = enum {
    Unmanaged,
    Pooled,
    SomeThirdThing,
};

entries: std.ArrayList(RegistryEntry),

pub fn init(allocator: Allocator) !Self {
    return .{
        .entries = std.ArrayList(RegistryEntry).init(allocator),
    };
}

pub fn addEntry(
    self: *Self,
    comptime config: EntryConfig,
    comptime initFn: InitFnTemplate(config),
    comptime deinitFn: DeinitFnTemplate(config),
) void {
    const EntryType = RegistryEntryType(config);

    const entry = RegistryEntry{
        .initFn = AnyPtr.fromDirect(EntryType.InitFnType, initFn),
        .deinitFn = AnyPtr.fromDirect(EntryType.DeinitFnType, deinitFn),

        .type_id = common.typeId(config.state),
        .type_name = @typeName(config.state),
        .management = config.management,
    };
    
    // If the type registry fails to build, there is literally nothing to be done about it.
    self.entries.append(entry) catch @panic("Failed to build type registry due to an allocation error!");
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

            return if (self.index < self.entries.len)
                &self.entries[self.index]
            else
                null;
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
