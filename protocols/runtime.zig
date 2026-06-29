const std = @import("std");
const builtin = @import("builtin");

/// Resolved at link time: kernel provides cooperative switch; standalone ELFs provide ecall stubs.
extern fn clarigggz_thread_yield() void;
extern fn clarigggz_adapter_log(ptr: [*]const u8, len: usize) void;
extern fn clarigggz_submit_intent(tap_id: u16, timestamp: u64, biometric: bool) void;

/// User-space syscall stubs for adapter processes.
pub const Syscall = enum(u64) {
    ipc_send = 1,
    ipc_recv = 2,
    yield = 3,
    get_cap = 4,
    submit_intent = 5,
    log = 255,
};

pub fn yield() void {
    if (comptime builtin.cpu.arch == .riscv64 and builtin.os.tag == .freestanding) {
        clarigggz_thread_yield();
    }
}

pub fn submitIntent(tap_id: u16, timestamp: u64, biometric: bool) void {
    if (comptime builtin.cpu.arch == .riscv64 and builtin.os.tag == .freestanding) {
        clarigggz_submit_intent(tap_id, timestamp, biometric);
    }
    _ = .{ tap_id, timestamp, biometric };
}

pub fn log(msg: []const u8) void {
    if (comptime builtin.cpu.arch == .riscv64 and builtin.os.tag == .freestanding) {
        clarigggz_adapter_log(msg.ptr, msg.len);
    } else if (builtin.os.tag != .freestanding) {
        std.debug.print("[adapter] {s}\n", .{msg});
    }
}
