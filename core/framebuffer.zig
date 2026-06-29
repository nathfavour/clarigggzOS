const std = @import("std");
const protocols = @import("protocols");
const builtin = @import("builtin");

/// Waveguide linear framebuffer (identity-mapped physical region).
pub const Framebuffer = struct {
    pub const default_base: u64 = 0x81000000;
    pub const default_width: u32 = 640;
    pub const default_height: u32 = 480;
    pub const bytes_per_pixel: u32 = 4;

    base: u64,
    width: u32,
    height: u32,
    pitch: u32,
    frame_counter: u64 = 0,

    pub fn init(base: u64) Framebuffer {
        const pitch = default_width * bytes_per_pixel;
        return .{
            .base = base,
            .width = default_width,
            .height = default_height,
            .pitch = pitch,
        };
    }

    pub fn info(self: *const Framebuffer) protocols.display.DisplayPort.FrameBufferInfo {
        return .{
            .width = self.width,
            .height = self.height,
            .pitch = self.pitch,
            .format = .rgba8888,
            .base_addr = self.base,
        };
    }

    pub fn pixels(self: *Framebuffer) [*]u32 {
        return @ptrFromInt(self.base);
    }

    pub fn clear(self: *Framebuffer, color: u32) void {
        const count = @as(usize, self.width) * @as(usize, self.height);
        const px = self.pixels();
        for (0..count) |i| {
            px[i] = color;
        }
    }

    pub fn fillRect(self: *Framebuffer, x: u32, y: u32, w: u32, h: u32, color: u32) void {
        const px = self.pixels();
        var row: u32 = 0;
        while (row < h) : (row += 1) {
            const py = y + row;
            if (py >= self.height) break;
            var col: u32 = 0;
            while (col < w) : (col += 1) {
                const px_x = x + col;
                if (px_x >= self.width) break;
                px[@as(usize, py) * self.width + px_x] = color;
            }
        }
    }

    /// Signal VSync — increments frame counter (hardware timer raises IRQ separately).
    pub fn signalVsync(self: *Framebuffer) protocols.display.DisplayPort.Event {
        self.frame_counter += 1;
        return .{ .vsync = .{ .timestamp_ns = self.frame_counter * 16_666_666 } };
    }

    pub fn mapRegion(self: *const Framebuffer, aspace: *@import("paging.zig").AddressSpace) !void {
        const size = @as(u64, self.width) * @as(u64, self.height) * @as(u64, bytes_per_pixel);
        var page: u64 = self.base;
        const end = self.base + size;
        const flags = @import("paging.zig").PTE.Flags.valid | @import("paging.zig").PTE.Flags.read | @import("paging.zig").PTE.Flags.write | @import("paging.zig").PTE.Flags.user;
        while (page < end) : (page += @import("paging.zig").AddressSpace.PageSize) {
            try aspace.map(page, page, flags);
        }
    }
};

test "Framebuffer geometry" {
    var fb = Framebuffer.init(Framebuffer.default_base);
    try std.testing.expectEqual(fb.info().width, 640);
    try std.testing.expectEqual(fb.signalVsync().vsync.timestamp_ns, 16_666_666);
}
