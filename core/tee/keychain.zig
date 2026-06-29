const std = @import("std");
const backend = @import("backend.zig");
const capability = @import("../capability.zig");

/// Clarigggz Keychain — sovereign secret store backed by Keystone TEE (or stub).
pub const max_items: usize = 64;
pub const max_blob_len: usize = 256;
pub const max_label_len: usize = 16;

pub const ItemKind = enum(u8) {
    passkey = 1,
    biometric_template = 2,
    seed_material = 3,
    liability_record = 4,
    generic_secret = 5,
    attestation_bundle = 6,
};

pub const ItemId = u32;
pub const invalid_item: ItemId = 0;

pub const Keychain = struct {
    backend: backend.TeeBackend,
    item_count: usize = 0,

    pub fn init(tee: backend.TeeBackend) Keychain {
        return .{ .backend = tee };
    }

    /// Seal arbitrary secret material. Returns opaque item handle.
    pub fn seal(self: *Keychain, kind: ItemKind, label: []const u8, data: []const u8) !ItemId {
        const id = try self.backend.seal(kind, label, data);
        self.item_count += 1;
        return id;
    }

    /// Open sealed item — caller must hold `keychain_slot` capability.
    pub fn open(self: *const Keychain, clist: *const capability.CList, cap_index: usize, item_id: ItemId, out: []u8) !usize {
        try assertKeychainCap(clist, cap_index, item_id, capability.Capability.Rights.read);
        return self.backend.open(item_id, out);
    }

    pub fn storePasskey(self: *Keychain, rp_id: []const u8, credential: []const u8) !ItemId {
        return self.seal(.passkey, rp_id, credential);
    }

    pub fn storeBiometricTemplate(self: *Keychain, sensor_id: []const u8, template: []const u8) !ItemId {
        self.backend.storeBiometricDigest(template);
        return self.seal(.biometric_template, sensor_id, template);
    }

    pub fn appendLiability(self: *Keychain, message: []const u8) void {
        self.backend.appendAudit(message);
        _ = self.seal(.liability_record, "intent-unlock", message) catch {};
    }

    pub fn storeSeed(self: *Keychain, wallet_label: []const u8, seed: []const u8) !ItemId {
        return self.seal(.seed_material, wallet_label, seed);
    }

    pub fn backendKind(self: *const Keychain) backend.BackendKind {
        return self.backend.vtable.kind;
    }
};

fn assertKeychainCap(clist: *const capability.CList, cap_index: usize, item_id: ItemId, required: u7) !void {
    const cap = clist.get(cap_index) orelse return error.MissingCapability;
    if (cap.cap_type != .keychain_slot) return error.WrongCapType;
    if (cap.object_id != item_id) return error.CapItemMismatch;
    if ((cap.rights & required) != required) return error.RightsViolation;
}

test "keychain passkey roundtrip via stub backend" {
    const stub = @import("stub_backend.zig");
    var kc = Keychain.init(stub.init(0));

    var clist: capability.CList = undefined;
    var caps_buf: [4]capability.Capability = undefined;
    for (&caps_buf) |*cap| {
        cap.* = .{
            .cap_type = .none,
            .rights = 0,
            .object_id = 0,
            .base = 0,
            .limit = 0,
        };
    }
    clist = .{ .caps = &caps_buf, .owner_id = 1 };

    const id = try kc.storePasskey("example.com", &[_]u8{ 0xAA, 0xBB });
    caps_buf[0] = .{
        .cap_type = .keychain_slot,
        .rights = capability.Capability.Rights.read,
        .object_id = @intCast(id),
        .base = 0,
        .limit = 0,
    };

    var out: [8]u8 = undefined;
    const n = try kc.open(&clist, 0, id, &out);
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqual(@as(u8, 0xAA), out[0]);
}
