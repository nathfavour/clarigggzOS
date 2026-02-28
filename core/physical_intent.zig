const std = @import("std");

/// A verifier for physical intent sequences (Layer 2 Security).
pub const PhysicalSequenceVerifier = struct {
    expected_sequence: [4]u16 = [_]u16{ 1, 3, 2, 4 }, // Example: Top, Bottom, Left, Right taps
    current_index: usize = 0,
    last_timestamp: u64 = 0,

    /// Verify a physical input sequence for "Intent-to-Unlock".
    pub fn verifyTap(self: *PhysicalSequenceVerifier, tap_id: u16, timestamp: u64) bool {
        // Time window for valid sequence (e.g., 2 seconds between taps)
        if (self.last_timestamp != 0 and (timestamp - self.last_timestamp > 2_000_000_000)) {
            self.current_index = 0; // Reset on timeout
        }

        if (tap_id == self.expected_sequence[self.current_index]) {
            self.current_index += 1;
            self.last_timestamp = timestamp;
            if (self.current_index == self.expected_sequence.len) {
                self.current_index = 0; // Reset for next verification
                return true;
            }
        } else {
            self.current_index = 0; // Reset on wrong sequence
        }
        return false;
    }
};
