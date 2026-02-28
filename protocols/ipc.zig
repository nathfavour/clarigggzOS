const std = @import("std");

/// Capability-based IPC message structure.
pub const Message = struct {
    sender_id: u32,
    protocol_id: u32,
    payload_len: u32,
    // Capabilities passed along with the message (e.g., page table rights).
    capability_bits: u64,
    payload: [128]u8, // Fixed-size small buffer for low latency.
};

/// The fundamental IPC interface for all Clarigggz adapters and the core.
pub const IPCInterface = struct {
    send: *const fn (msg: Message) anyerror!void,
    recv: *const fn () anyerror!Message,
};
