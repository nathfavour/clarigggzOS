const std = @import("std");
const physical_intent = @import("physical_intent.zig");

/// The security state of the Clarigggz OS.
pub const SecurityState = enum(u8) {
    sandbox = 0,
    unlocked = 1,
};

/// Write-only liability log ring buffer (Article IV: Liability Shift).
pub const LiabilityLog = struct {
    entries: [16][64]u8,
    lengths: [16]u8,
    head: u8 = 0,
    count: u8 = 0,

    pub fn append(self: *LiabilityLog, message: []const u8) void {
        const idx = self.head;
        const len = @min(message.len, 63);
        @memcpy(self.entries[idx][0..len], message[0..len]);
        self.entries[idx][len] = 0;
        self.lengths[idx] = @intCast(len);
        self.head = (self.head + 1) % 16;
        if (self.count < 16) self.count += 1;
    }

    pub fn latest(self: *const LiabilityLog) ?[]const u8 {
        if (self.count == 0) return null;
        const idx = if (self.head == 0) 15 else self.head - 1;
        return self.entries[idx][0..self.lengths[idx]];
    }
};

/// The "Intent-to-Unlock" protocol handler.
pub const SecurityManager = struct {
    state: SecurityState = .sandbox,
    biometric_verified: bool = false,
    physical_intent_verified: bool = false,
    liability_log: LiabilityLog = .{
        .entries = [_][64]u8{[_]u8{0} ** 64} ** 16,
        .lengths = [_]u8{0} ** 16,
    },

    pub fn handleTactileEvent(
        self: *SecurityManager,
        verifier: *physical_intent.PhysicalSequenceVerifier,
        tap_id: u16,
        timestamp: u64,
        biometric: bool,
        emit: fn (msg: []const u8) void,
    ) void {
        self.biometric_verified = biometric;
        self.physical_intent_verified = verifier.verifyTap(tap_id, timestamp);

        if (self.physical_intent_verified and biometric) {
            self.storeBiometric(&[_]u8{ 0xDE, 0xAD, 0xBE, 0xEF }, emit);
            self.attemptUnlock(biometric, true, emit) catch {
                emit("[Security] Unlock consensus failed\n");
            };
        } else if (self.physical_intent_verified) {
            emit("[Security] Physical sequence verified; awaiting biometric\n");
        }
    }

    pub fn attemptUnlock(self: *SecurityManager, biometric: bool, physical: bool, emit: fn (msg: []const u8) void) !void {
        if (biometric and physical) {
            self.state = .unlocked;
            try self.logLiabilityShift(emit);
        } else {
            return error.SecurityConsensusFailed;
        }
    }

    pub fn relock(self: *SecurityManager, tamper_check: bool) void {
        if (tamper_check) {
            self.state = .sandbox;
            self.biometric_verified = false;
            self.physical_intent_verified = false;
        }
    }

    fn logLiabilityShift(self: *SecurityManager, emit: fn (msg: []const u8) void) !void {
        const msg = "LIABILITY SHIFT: User assumed full hardware control.";
        self.liability_log.append(msg);
        if (@import("builtin").os.tag == .freestanding) {
            @import("main.zig").secure_enclave.appendLiability(msg);
        }
        emit("[Security] ");
        emit(msg);
        emit("\n");
    }

    pub fn storeBiometric(self: *SecurityManager, digest: []const u8, emit: fn (msg: []const u8) void) void {
        if (@import("builtin").os.tag == .freestanding) {
            @import("main.zig").secure_enclave.storeBiometricDigest(digest);
        }
        emit("[Security] Biometric digest sealed in enclave\n");
        _ = self;
    }
};

test "Security - Intent to Unlock flow" {
    var mgr = SecurityManager{};
    var verifier = physical_intent.PhysicalSequenceVerifier{};
    const noop = struct {
        fn f(_: []const u8) void {}
    }.f;

    const seq = [_]struct { u16, u64, bool }{
        .{ 1, 100, false },
        .{ 3, 200, false },
        .{ 2, 300, false },
        .{ 4, 400, true },
    };
    for (seq) |step| {
        mgr.handleTactileEvent(&verifier, step[0], step[1], step[2], noop);
    }
    try std.testing.expectEqual(mgr.state, .unlocked);
    try std.testing.expect(mgr.liability_log.latest() != null);
}
