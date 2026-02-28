const std = @import("std");

/// InputPort protocol for spatial and biometric input.
pub const InputPort = struct {
    pub const ProtocolID: u32 = 0xCAF2;

    pub const SpatialEvent = struct {
        x: f32,
        y: f32,
        z: f32,
        pressure: f32,
        event_type: enum(u8) { tap, swipe, hold, pinch },
    };

    pub const BiometricEvent = struct {
        verified: bool,
        user_id: u32,
        confidence: f32, // Pareto-optimized local inference result
    };

    pub const Event = union(enum) {
        spatial: SpatialEvent,
        biometric: BiometricEvent,
        physical_intent: struct { sequence_id: u16 },
    };
};
