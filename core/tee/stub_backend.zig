const std = @import("std");
const builtin = @import("builtin");
const backend = @import("backend.zig");
const sbi = @import("sbi_contract.zig");
const keychain = @import("keychain.zig");
const layout = @import("layout.zig");

/// In-memory software vault used until Keystone PMP enclaves are online.
pub const StubVault = struct {
    base: u64,
    write_index: u32 = 0,
    next_item_id: u32 = 1,
    items: [keychain.max_items]StoredItem = undefined,
    item_count: usize = 0,
    tamper_flag: bool = false,

    pub const record_size: usize = 64;
    pub const max_audit_records: usize = 32;

    const StoredItem = struct {
        id: u32,
        kind: keychain.ItemKind,
        label: [16]u8,
        label_len: u8,
        data: [keychain.max_blob_len]u8,
        data_len: u16,
        active: bool = false,
    };

    pub fn init(base: u64) StubVault {
        return .{ .base = base };
    }

    inline fn auditSlot(self: *StubVault, index: u32) [*]volatile u8 {
        const offset = 8 + @as(u64, index) * record_size;
        return @ptrFromInt(self.base + offset);
    }

    inline fn auditHeader(self: *StubVault) *volatile u32 {
        return @ptrFromInt(self.base);
    }

    pub fn appendAuditRecord(self: *StubVault, message: []const u8) void {
        if (comptime builtin.os.tag != .freestanding) {
            self.write_index = @intCast((self.write_index + 1) % max_audit_records);
            return;
        }
        const idx: u32 = @intCast(self.write_index % max_audit_records);
        const dest = self.auditSlot(idx);
        const len = @min(message.len, record_size - 1);
        var i: usize = 0;
        while (i < len) : (i += 1) dest[i] = message[i];
        dest[len] = 0;
        self.write_index += 1;
        self.auditHeader().* = self.write_index;
    }

    pub fn storeItem(self: *StubVault, kind: keychain.ItemKind, label: []const u8, data: []const u8) !u32 {
        if (self.item_count >= self.items.len) return error.VaultFull;
        const id = self.next_item_id;
        self.next_item_id += 1;

        var item = StoredItem{
            .id = id,
            .kind = kind,
            .label = undefined,
            .label_len = @intCast(@min(label.len, 16)),
            .data = undefined,
            .data_len = @intCast(@min(data.len, keychain.max_blob_len)),
        };
        @memset(&item.label, 0);
        @memset(&item.data, 0);
        @memcpy(item.label[0..item.label_len], label[0..item.label_len]);
        @memcpy(item.data[0..item.data_len], data[0..item.data_len]);
        item.active = true;

        self.items[self.item_count] = item;
        self.item_count += 1;
        return id;
    }

    pub fn openItem(self: *const StubVault, item_id: u32, out: []u8) !usize {
        for (self.items[0..self.item_count]) |item| {
            if (!item.active or item.id != item_id) continue;
            const len = @min(item.data_len, out.len);
            @memcpy(out[0..len], item.data[0..len]);
            return len;
        }
        return error.ItemNotFound;
    }
};

var vault_storage: StubVault = undefined;

fn sealBlob(ctx: *anyopaque, kind: keychain.ItemKind, label: []const u8, data: []const u8) !u32 {
    const vault: *StubVault = @ptrCast(@alignCast(ctx));
    return vault.storeItem(kind, label, data);
}

fn openBlob(ctx: *anyopaque, item_id: u32, out: []u8) !usize {
    const vault: *StubVault = @ptrCast(@alignCast(ctx));
    return vault.openItem(item_id, out);
}

fn appendAudit(ctx: *anyopaque, message: []const u8) void {
    const vault: *StubVault = @ptrCast(@alignCast(ctx));
    vault.appendAuditRecord(message);
}

fn storeBiometric(ctx: *anyopaque, digest: []const u8) void {
    const vault: *StubVault = @ptrCast(@alignCast(ctx));
    const prefix = "BIO:";
    var buf: [StubVault.record_size]u8 = undefined;
    @memset(&buf, 0);
    const prefix_len = @min(prefix.len, buf.len);
    @memcpy(buf[0..prefix_len], prefix[0..prefix_len]);
    const copy_len = @min(digest.len, buf.len - prefix_len);
    @memcpy(buf[prefix_len .. prefix_len + copy_len], digest[0..copy_len]);
    vault.appendAuditRecord(buf[0 .. prefix_len + copy_len]);
    _ = vault.storeItem(.biometric_template, "tactile-id", digest) catch {};
}

fn spawnEnclaveStub(_: *anyopaque, _: *const sbi.CreateArgs) !backend.EnclaveId {
    return error.BackendNotReady;
}

fn destroyEnclaveStub(_: *anyopaque, _: backend.EnclaveId) !void {
    return error.BackendNotReady;
}

fn deriveSealingKeyStub(_: *anyopaque, _: []const u8, _: *[sbi.SEALING_KEY_SIZE]u8) !void {
    return error.BackendNotReady;
}

const stub_vtable = backend.VTable{
    .kind = .stub,
    .seal_blob = sealBlob,
    .open_blob = openBlob,
    .append_audit = appendAudit,
    .store_biometric_digest = storeBiometric,
    .spawn_enclave = spawnEnclaveStub,
    .destroy_enclave = destroyEnclaveStub,
    .derive_sealing_key = deriveSealingKeyStub,
};

pub fn init(base: u64) backend.TeeBackend {
    vault_storage = StubVault.init(base);
    return .{
        .ctx = &vault_storage,
        .vtable = &stub_vtable,
    };
}

pub fn defaultBase() u64 {
    return layout.active.legacy_stub_enclave_base;
}

test "stub vault stores passkey" {
    var tee = init(0);
    const id = try tee.seal(.passkey, "wifi-home", &[_]u8{ 0x01, 0x02 });
    var buf: [32]u8 = undefined;
    const n = try tee.open(id, &buf);
    try std.testing.expectEqual(@as(usize, 2), n);
}
