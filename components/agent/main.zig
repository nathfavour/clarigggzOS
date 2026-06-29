const std = @import("std");
const protocols = @import("protocols");
const runtime = protocols.runtime;
const AgentPort = protocols.agent.AgentPort;

pub const std_options_debug_threaded_io: ?*anyopaque = null;

fn adapterMain() void {
    runtime.log("agent-runtime: spatial planner online");

    var ticks: usize = 0;
    while (ticks < 200) : (ticks += 1) {
        const task = AgentPort.Task{
            .kind = .infer,
            .agent_id = 1,
            .priority = 4,
            .token_budget = 64,
            .payload_len = 0,
        };
        _ = task;
        runtime.yield();
    }
}

pub export fn clarigggz_agent_entry() callconv(.c) noreturn {
    adapterMain();
    while (true) {
        runtime.yield();
    }
}

const builtin = @import("builtin");
const config = @import("config");

fn startShim() callconv(.c) noreturn {
    clarigggz_agent_entry();
}

fn threadYieldEcall() callconv(.c) void {
    asm volatile (
        \\li a0, 3
        \\ecall
        ::: .{ .memory = true }
    );
}

comptime {
    if (builtin.os.tag == .freestanding and !config.kernel_adapter) {
        @export(&startShim, .{ .name = "_start", .linkage = .strong });
        @export(&threadYieldEcall, .{ .name = "clarigggz_thread_yield", .linkage = .weak });
    }
}

pub fn main() !void {
    adapterMain();
}
