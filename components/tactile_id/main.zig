const std = @import("std");
const protocols = @import("protocols");
const InputPort = protocols.input.InputPort;
const runtime = protocols.runtime;

pub const std_options_debug_threaded_io: ?*anyopaque = null;

fn adapterMain() void {
    runtime.log("tactile-id: biometric adapter online");

    const unlock_sequence = [_]u16{ 1, 3, 2, 4 };
    var loops: usize = 0;
    while (loops < 200) : (loops += 1) {
        if (loops < unlock_sequence.len) {
            const tap = unlock_sequence[loops];
            const event = InputPort.Event{
                .biometric = .{
                    .verified = loops == unlock_sequence.len - 1,
                    .user_id = 1,
                    .confidence = 0.99,
                },
            };
            _ = event;
            runtime.submitIntent(tap, @intCast(loops * 100_000_000), loops == unlock_sequence.len - 1);
        }
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
