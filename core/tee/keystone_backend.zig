const std = @import("std");
const builtin = @import("builtin");
const config = @import("config");
const backend = @import("backend.zig");
const sbi = @import("sbi_contract.zig");
const keychain = @import("keychain.zig");
const stub = @import("stub_backend.zig");

/// Host-side bridge to the Keystone Security Monitor.
///
/// Activated when `config.tee_backend == "keystone"`. Requires the SM to be the
/// M-mode reset vector and Clarigggz to enter at `layout.active.kernel_base`.
///
/// WIP upstream: `~/code/nathfavour/keystore/keystone-zig`
pub const KeystoneBridge = struct {
    /// Local audit trail until enclave keychain service is spawned.
    fallback: stub.StubVault,
    next_pool_offset: u64 = 0,

    pub fn init(fallback_base: u64) KeystoneBridge {
        return .{
            .fallback = stub.StubVault.init(fallback_base),
        };
    }
};

fn ecall(fid: sbi.Fid, arg0: usize, arg1: usize, arg2: usize, arg3: usize, arg4: usize, arg5: usize) sbi.SbiRet {
    if (comptime builtin.os.tag != .freestanding) {
        return .{ .error_code = @intFromEnum(sbi.Error.not_implemented), .value = 0 };
    }
    var err: isize = undefined;
    var val: usize = undefined;
    asm volatile (
        \\mv a7, %[ext]
        \\mv a6, %[fid]
        \\mv a0, %[a0]
        \\mv a1, %[a1]
        \\mv a2, %[a2]
        \\mv a3, %[a3]
        \\mv a4, %[a4]
        \\mv a5, %[a5]
        \\ecall
        \\mv %[err], a0
        \\mv %[val], a1
        :
        [err] "=r" (err),
        [val] "=r" (val),
        :
        [ext] "r" (@as(usize, sbi.extension_id)),
        [fid] "r" (@as(usize, @intFromEnum(fid))),
        [a0] "r" (arg0),
        [a1] "r" (arg1),
        [a2] "r" (arg2),
        [a3] "r" (arg3),
        [a4] "r" (arg4),
        [a5] "r" (arg5),
        : .{ .memory = true }
    );
    return .{ .error_code = @intCast(err), .value = val };
}

fn sealBlob(ctx: *anyopaque, kind: keychain.ItemKind, label: []const u8, data: []const u8) !u32 {
    const bridge: *KeystoneBridge = @ptrCast(@alignCast(ctx));
    return bridge.fallback.storeItem(kind, label, data);
}

fn openBlob(ctx: *anyopaque, item_id: u32, out: []u8) !usize {
    const bridge: *KeystoneBridge = @ptrCast(@alignCast(ctx));
    return bridge.fallback.openItem(item_id, out);
}

fn appendAudit(ctx: *anyopaque, message: []const u8) void {
    const bridge: *KeystoneBridge = @ptrCast(@alignCast(ctx));
    bridge.fallback.appendAuditRecord(message);
}

fn storeBiometric(ctx: *anyopaque, digest: []const u8) void {
    const bridge: *KeystoneBridge = @ptrCast(@alignCast(ctx));
    bridge.fallback.appendAuditRecord("BIO: sealed");
    _ = bridge.fallback.storeItem(.biometric_template, "tactile-id", digest) catch {};
}

fn spawnEnclave(ctx: *anyopaque, args: *const sbi.CreateArgs) !backend.EnclaveId {
    const bridge: *KeystoneBridge = @ptrCast(@alignCast(ctx));
    _ = bridge;
    const ret = ecall(.create_enclave, @intFromPtr(args), 0, 0, 0, 0, 0);
    if (!ret.ok()) return error.SbiFailure;
    return @intCast(ret.value);
}

fn destroyEnclave(_: *anyopaque, eid: backend.EnclaveId) !void {
    const ret = ecall(.destroy_enclave, eid, 0, 0, 0, 0, 0);
    if (!ret.ok()) return error.SbiFailure;
}

fn deriveSealingKey(_: *anyopaque, key_id: []const u8, out: *[sbi.SEALING_KEY_SIZE]u8) !void {
    _ = key_id;
    _ = out;
    // Enclave-only FID today; host broker will proxy via `wallet-core` enclave.
    return error.NotImplemented;
}

const keystone_vtable = backend.VTable{
    .kind = .keystone,
    .seal_blob = sealBlob,
    .open_blob = openBlob,
    .append_audit = appendAudit,
    .store_biometric_digest = storeBiometric,
    .spawn_enclave = spawnEnclave,
    .destroy_enclave = destroyEnclave,
    .derive_sealing_key = deriveSealingKey,
};

var bridge_storage: KeystoneBridge = undefined;

pub fn init(fallback_base: u64) backend.TeeBackend {
    bridge_storage = KeystoneBridge.init(fallback_base);
    return .{
        .ctx = &bridge_storage,
        .vtable = &keystone_vtable,
    };
}

pub fn isRequested() bool {
    return std.mem.eql(u8, config.tee_backend, "keystone");
}
