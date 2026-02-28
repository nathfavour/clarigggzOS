const std = @import("std");

/// The security state of the Clarigggz OS.
pub const SecurityState = enum(u8) {
    sandbox = 0,    // Default: Strict thermal and scheduling invariants.
    unlocked = 1,   // User-controlled: Liability shifted to the user.
};

/// The "Intent-to-Unlock" protocol handler.
pub const SecurityManager = struct {
    state: SecurityState = .sandbox,
    biometric_verified: bool = false,
    physical_intent_verified: bool = false,

    /// Transition to the Unlocked state via physical consensus.
    /// Article IV: Requires Biometric (Layer 1) + Physical Intent (Layer 2).
    pub fn attemptUnlock(self: *SecurityManager, biometric: bool, physical: bool) !void {
        if (biometric and physical) {
            self.state = .unlocked;
            try self.logLiabilityShift();
        } else {
            return error.SecurityConsensusFailed;
        }
    }

    /// Merciful Relocking: Restore default protections if no tampering is detected.
    pub fn relock(self: *SecurityManager, tamper_check: bool) void {
        if (tamper_check) {
            self.state = .sandbox;
        }
    }

    /// The Liability Shift: Log the transition to a write-only secure enclave.
    fn logLiabilityShift(self: *const SecurityManager) !void {
        _ = self;
        // In a real K1 implementation, this would write to a protected MMIO region
        // or a dedicated secure flash partition.
        // std.debug.print("LIABILITY SHIFT: User has assumed full hardware control.
", .{});
    }
};
