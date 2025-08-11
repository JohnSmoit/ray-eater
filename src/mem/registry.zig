const std = @import("std");

const common = @import("common.zig");
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
};


// this returns the meta-information of the registry entry
// (underlying function types, unique type identifier)
pub fn RegistryEntryType(comptime config: EntryConfig) type {
    return struct {
        // remember, these functions should be remapped first arguments to the proxy
        pub const InitFnType = InitFnTemplate(config),
        pub const DeinitFnType = DeinitFnTemplate(config),
        pub const entry_id = helpers.typeId(config.state);
    };
};


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
    initFn: AnyPtr,
    deinitFn: AnyPtr,
};

// Radix-sorted list of entries by type id
const entries: []RegistryEntry;

pub fn AddEntry(
    self: *Self,
    comptime config: EntryConfig,
    initFn: InitFnTemplate(config),
    deinitFn: DeinitFnTemplate(config),
) *const RegistryEntry {
    const EntryType = RegistryEntryType(config);
    const entry = RegistryEntry{
        .initFn = AnyPtr.from(EntryType.InitFn, initFn),
        .deinitFn = AntPtr.from(EntryType.DeinitFn, deinitFn),
    };

}
