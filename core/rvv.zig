const std = @import("std");
const builtin = @import("builtin");

/// RISC-V Vector Extension (RVV 1.0) state tracked by the Core Broker.
pub const RvvState = struct {
    vlen_bytes: usize = 0,
    enabled: bool = false,
};

pub var global: RvvState = .{};

/// Initialize RVV 1.0 at boot: verify VLEN and mark vector unit ready.
pub fn init() void {
    if (comptime builtin.cpu.arch != .riscv64) {
        global = .{ .vlen_bytes = 16, .enabled = false };
        return;
    }

    if (comptime builtin.os.tag == .freestanding) {
        var vlenb: usize = undefined;
        asm volatile ("csrr %[vlenb], vlenb" : [vlenb] "=r" (vlenb));

        // Ensure VS field in sstatus is Initial (01) — boot.S sets this; confirm here.
        var sstatus: u64 = undefined;
        asm volatile ("csrr %[sstatus], sstatus" : [sstatus] "=r" (sstatus));
        const vs_mask: u64 = 0x00000600;
        if ((sstatus & vs_mask) == 0) {
            asm volatile ("csrs sstatus, %[mask]" : : [mask] "r" (vs_mask));
        }

        global = .{
            .vlen_bytes = vlenb,
            .enabled = vlenb > 0,
        };
    } else {
        global = .{ .vlen_bytes = 16, .enabled = false };
    }
}

pub fn logStatus(print: fn ([]const u8) void) void {
    print("[RVV] Vector unit ");
    if (global.enabled) {
        print("enabled, VLEN=");
        printUsize(global.vlen_bytes, print);
        print(" bytes\n");
    } else {
        print("unavailable (simulator/host)\n");
    }
}

fn printUsize(val: usize, print: fn ([]const u8) void) void {
    var buf: [32]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "{d}", .{val}) catch {
        print("?");
        return;
    };
    print(out);
}

test "RVV init on host" {
    init();
    try std.testing.expect(global.vlen_bytes > 0);
}
