//! @deprecated Use `core/tee/keychain.zig` via `main.clarigggz_keychain`.
const tee = @import("tee/root.zig");

pub const SecureEnclave = struct {
    pub const qemu_virt_base: u64 = tee.layout.active.legacy_stub_enclave_base;
    pub const record_size: usize = 64;
    pub const max_records: usize = 32;

    base: u64,

    pub fn init(base: u64) SecureEnclave {
        return .{ .base = base };
    }

    pub fn appendLiability(self: *SecureEnclave, message: []const u8) void {
        _ = self;
        _ = message;
    }

    pub fn storeBiometricDigest(self: *SecureEnclave, digest: []const u8) void {
        _ = self;
        _ = digest;
    }

    pub fn recordCount(self: *const SecureEnclave) u32 {
        _ = self;
        return 0;
    }

    pub fn markTamper(self: *SecureEnclave) void {
        _ = self;
    }
};
