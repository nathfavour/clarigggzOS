//! Platform memory layout contract shared with keystone-zig.
//!
//! When Clarigggz boots under the Keystone Security Monitor, the SM owns
//! M-mode firmware at `sm_base` and hands off S-mode to the kernel at
//! `kernel_base`. Enclave private memory is carved from `enclave_pool_base`.
//!
//! Source of truth (WIP): `~/code/nathfavour/keystore/keystone-zig/lib/layout.zig`

const std = @import("std");
const config = @import("config");

pub const TargetHardware = enum {
    qemu_virt,
    spacemit_k1,
};

pub const current_hardware: TargetHardware = if (std.mem.eql(u8, config.hardware, "spacemit_k1"))
    .spacemit_k1
else
    .qemu_virt;

/// QEMU `virt` profile — aligned with keystone-zig `layout.qemu_virt`.
pub const QemuVirt = struct {
    pub const sm_base: u64 = 0x8000_0000;
    pub const sm_size: u64 = 0x0010_0000;

    pub const kernel_base: u64 = 0x8020_0000;
    pub const kernel_size: u64 = 0x0100_0000;

    pub const enclave_pool_base: u64 = 0x9000_0000;
    pub const enclave_pool_size: u64 = 0x1000_0000;

    /// Per-enclave untrusted shared memory (UTM) for host↔enclave IPC.
    pub const default_utm_size: u64 = 0x10_0000;

    /// Legacy Clarigggz software-enclave MMIO stub (replaced by Keystone PMP).
    pub const legacy_stub_enclave_base: u64 = 0x1000_1000;
};

/// SpacemiT K1 — placeholder until keystone-zig adds a K1 profile.
pub const SpacemitK1 = struct {
    pub const sm_base: u64 = 0x0000_0000; // TBD with silicon PMP map
    pub const sm_size: u64 = 0x0010_0000;
    pub const kernel_base: u64 = 0x8020_0000;
    pub const kernel_size: u64 = 0x0100_0000;
    pub const enclave_pool_base: u64 = 0x9000_0000;
    pub const enclave_pool_size: u64 = 0x1000_0000;
    pub const default_utm_size: u64 = 0x10_0000;
    pub const legacy_stub_enclave_base: u64 = 0x1000_1000;
};

pub const active = switch (current_hardware) {
    .qemu_virt => QemuVirt,
    .spacemit_k1 => SpacemitK1,
};

test "kernel entry matches linker script" {
    try std.testing.expectEqual(@as(u64, 0x8020_0000), active.kernel_base);
}
