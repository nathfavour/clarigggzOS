const adapter_loader = @import("adapter_loader.zig");
const compositor_adapter = @import("compositor_adapter");
const neural_adapter = @import("neural_adapter");
const tactile_adapter = @import("tactile_adapter");
const agent_adapter = @import("agent_adapter");

pub const Loader = adapter_loader.Loader;

pub const builtin_descriptors = [_]adapter_loader.AdapterDescriptor{
    .{ .name = "compositor", .entry = compositor_adapter.clarigggz_compositor_entry, .priority = 5 },
    .{ .name = "neural-engine", .entry = neural_adapter.clarigggz_neural_entry, .priority = 8 },
    .{ .name = "tactile-id", .entry = tactile_adapter.clarigggz_tactile_entry, .priority = 3 },
    .{ .name = "agent-runtime", .entry = agent_adapter.clarigggz_agent_entry, .priority = 4 },
};
