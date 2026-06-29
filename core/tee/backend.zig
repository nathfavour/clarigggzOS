const std = @import("std");
const sbi = @import("sbi_contract.zig");

/// Which TEE implementation backs the Clarigggz Keychain.
pub const BackendKind = enum {
    /// Software MMIO stub — development / simulator only.
    stub,
    /// Keystone Security Monitor via SBI extension `0x08424b45`.
    keystone,
};

pub const EnclaveId = u32;
pub const invalid_enclave: EnclaveId = 0xffff_ffff;

pub const ItemHandle = struct {
    id: u32,
    kind: @import("keychain.zig").ItemKind,
};

/// Operations every TEE backend must provide to the Keychain broker.
pub const VTable = struct {
    kind: BackendKind,

    seal_blob: *const fn (
        ctx: *anyopaque,
        kind: @import("keychain.zig").ItemKind,
        label: []const u8,
        data: []const u8,
    ) anyerror!u32,

    open_blob: *const fn (
        ctx: *anyopaque,
        item_id: u32,
        out: []u8,
    ) anyerror!usize,

    append_audit: *const fn (ctx: *anyopaque, message: []const u8) void,

    store_biometric_digest: *const fn (ctx: *anyopaque, digest: []const u8) void,

    /// Host-only: spawn a Keystone enclave (no-op on stub backend).
    spawn_enclave: *const fn (
        ctx: *anyopaque,
        args: *const sbi.CreateArgs,
    ) anyerror!EnclaveId,

    destroy_enclave: *const fn (ctx: *anyopaque, eid: EnclaveId) anyerror!void,

    derive_sealing_key: *const fn (
        ctx: *anyopaque,
        key_id: []const u8,
        out: *[sbi.SEALING_KEY_SIZE]u8,
    ) anyerror!void,
};

pub const TeeBackend = struct {
    ctx: *anyopaque,
    vtable: *const VTable,

    pub fn seal(
        self: *const TeeBackend,
        kind: @import("keychain.zig").ItemKind,
        label: []const u8,
        data: []const u8,
    ) !u32 {
        return self.vtable.seal_blob(self.ctx, kind, label, data);
    }

    pub fn open(self: *const TeeBackend, item_id: u32, out: []u8) !usize {
        return self.vtable.open_blob(self.ctx, item_id, out);
    }

    pub fn appendAudit(self: *const TeeBackend, message: []const u8) void {
        self.vtable.append_audit(self.ctx, message);
    }

    pub fn storeBiometricDigest(self: *const TeeBackend, digest: []const u8) void {
        self.vtable.store_biometric_digest(self.ctx, digest);
    }

    pub fn spawnEnclave(self: *const TeeBackend, args: *const sbi.CreateArgs) !EnclaveId {
        return self.vtable.spawn_enclave(self.ctx, args);
    }

    pub fn destroyEnclave(self: *const TeeBackend, eid: EnclaveId) !void {
        return self.vtable.destroy_enclave(self.ctx, eid);
    }

    pub fn deriveSealingKey(self: *const TeeBackend, key_id: []const u8, out: *[sbi.SEALING_KEY_SIZE]u8) !void {
        return self.vtable.derive_sealing_key(self.ctx, key_id, out);
    }
};
