const std = @import("std");
const protocols = @import("protocols");
const InputPort = protocols.input.InputPort;
const runtime = protocols.runtime;

pub const std_options_debug_threaded_io: ?*anyopaque = null;

fn adapterMain() void {
    runtime.log("tactile-id: biometric adapter online");

    var loops: usize = 0;
    while (loops < 100) : (loops += 1) {
        runtime.yield();
    }
}

pub export fn clarigggz_tactile_entry() callconv(.c) noreturn {
    adapterMain();
    while (true) {
        runtime.yield();
    }
}

const builtin = @import("builtin");
const config = @import("config");

fn startShim() callconv(.c) noreturn {
    clarigggz_tactile_entry();
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
