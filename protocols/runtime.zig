const std = @import("std");
const builtin = @import("builtin");

/// Resolved at link time: kernel provides cooperative switch; standalone ELFs provide ecall stub.
extern fn clarigggz_thread_yield() void;

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
        asm volatile (
            \\li a0, 5
            \\mv a1, %[tap]
            \\mv a2, %[ts]
            \\mv a3, %[bio]
            \\ecall
            :
            : [tap] "r" (@as(u64, tap_id)),
              [ts] "r" (timestamp),
              [bio] "r" (@as(u64, if (biometric) 1 else 0))
            : .{ .memory = true }
        );
    }
    _ = .{ tap_id, timestamp, biometric };
}

pub fn log(msg: []const u8) void {
    if (comptime builtin.cpu.arch == .riscv64 and builtin.os.tag == .freestanding) {
        asm volatile (
            \\li a0, 255
            \\mv a1, %[ptr]
            \\mv a2, %[len]
            \\ecall
            :
            : [ptr] "r" (@intFromPtr(msg.ptr)),
              [len] "r" (msg.len)
            : .{ .memory = true }
        );
    } else if (builtin.os.tag != .freestanding) {
        std.debug.print("[adapter] {s}\n", .{msg});
    }
}
