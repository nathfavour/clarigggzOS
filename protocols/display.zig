const std = @import("std");

/// DisplayPort protocol for spatial compositing and frame buffer management.
pub const DisplayPort = struct {
    pub const ProtocolID: u32 = 0xCAF1;

    pub const FrameBufferInfo = struct {
        width: u32,
        height: u32,
        pitch: u32,
        format: enum(u8) { rgba8888, bgra8888, rgb565 },
        base_addr: u64,
    };

    pub const Event = union(enum) {
        vsync: struct { timestamp_ns: u64 },
        frame_ready: struct { buffer_index: u8 },
        config_change: FrameBufferInfo,
    };
};
