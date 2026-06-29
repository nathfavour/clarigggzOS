const std = @import("std");
const builtin = @import("builtin");

/// Software secure enclave: write-only MMIO region for biometric hashes and liability records.
pub const SecureEnclave = struct {
    pub const qemu_virt_base: u64 = 0x10001000;
    pub const record_size: usize = 64;
    pub const max_records: usize = 32;

    base: u64,
    write_index: u32 = 0,
    tamper_flag: bool = false,

    pub fn init(base: u64) SecureEnclave {
        return .{ .base = base };
    }

    inline fn slot(self: *SecureEnclave, index: u32) [*]volatile u8 {
        const offset = 8 + @as(u64, index) * record_size;
        return @ptrFromInt(self.base + offset);
    }

    inline fn header(self: *SecureEnclave) *volatile u32 {
        return @ptrFromInt(self.base);
    }

    pub fn appendLiability(self: *SecureEnclave, message: []const u8) void {
        if (comptime builtin.os.tag != .freestanding) {
            self.write_index = (self.write_index + 1) % max_records;
            return;
        }
        const idx = self.write_index % max_records;
        const dest = self.slot(idx);
        const len = @min(message.len, record_size - 1);
        var i: usize = 0;
        while (i < len) : (i += 1) {
            dest[i] = message[i];
        }
        dest[len] = 0;
        self.write_index += 1;
        self.header().* = self.write_index;
    }

    pub fn storeBiometricDigest(self: *SecureEnclave, digest: []const u8) void {
        const prefix = "BIO:";
        var buf: [record_size]u8 = undefined;
        @memset(&buf, 0);
        const prefix_len = @min(prefix.len, buf.len);
        @memcpy(buf[0..prefix_len], prefix[0..prefix_len]);
        const copy_len = @min(digest.len, buf.len - prefix_len);
        @memcpy(buf[prefix_len .. prefix_len + copy_len], digest[0..copy_len]);
        self.appendLiability(buf[0 .. prefix_len + copy_len]);
    }

    pub fn recordCount(self: *const SecureEnclave) u32 {
        if (comptime builtin.os.tag != .freestanding) return self.write_index;
        return self.header().*;
    }

    pub fn markTamper(self: *SecureEnclave) void {
        self.tamper_flag = true;
    }
};

test "Secure enclave records" {
    var enc = SecureEnclave.init(0);
    enc.appendLiability("test liability");
    try std.testing.expect(enc.recordCount() > 0);
    enc.storeBiometricDigest(&[_]u8{ 0xAA, 0xBB, 0xCC });
}
