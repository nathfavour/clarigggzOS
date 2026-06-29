const std = @import("std");
const protocols = @import("protocols");
const DisplayPort = protocols.display.DisplayPort;
const runtime = protocols.runtime;

pub const std_options_debug_threaded_io: ?*anyopaque = null;

pub const Window = struct {
    title: []const u8,
    content: []const u8,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
};

pub const DesktopEnvironment = struct {
    windows: [4]Window,
    window_count: usize,
    width: u32,
    height: u32,

    pub fn init() DesktopEnvironment {
        return .{
            .windows = [_]Window{
                .{ .title = "Agent Workspace", .content = "auracrab-purple-48: status=connected", .x = 3, .y = 3, .width = 44, .height = 7 },
                .{ .title = "System Monitor", .content = "CPU: 1.2% | RAM: 284/1024KB", .x = 50, .y = 3, .width = 27, .height = 5 },
                .{ .title = "M2M IPC Log", .content = "Port 200: IRQ 7 claimed.", .x = 3, .y = 12, .width = 74, .height = 7 },
                .{ .title = "", .content = "", .x = 0, .y = 0, .width = 0, .height = 0 },
            },
            .window_count = 3,
            .width = 80,
            .height = 24,
        };
    }

    pub fn draw(self: *const DesktopEnvironment) void {
        var buffer: [24][80]u8 = undefined;
        for (0..24) |y| {
            for (0..80) |x| {
                if (y == 0 or y == 23) {
                    buffer[y][x] = '=';
                } else {
                    buffer[y][x] = if ((x + y) % 4 == 0) '.' else ' ';
                }
            }
        }
        for (0..self.window_count) |w_idx| {
            const w = self.windows[w_idx];
            for (0..w.height) |dy| {
                const py = w.y + dy;
                if (py >= 24) continue;
                for (0..w.width) |dx| {
                    const px = w.x + dx;
                    if (px >= 80) continue;
                    if (dy == 0 or dy == w.height - 1) {
                        buffer[py][px] = '-';
                    } else if (dx == 0 or dx == w.width - 1) {
                        buffer[py][px] = '|';
                    }
                }
            }
            if (w.title.len > 0) {
                const title_start = w.x + 2;
                for (0..w.title.len) |ti| {
                    if (title_start + ti < w.x + w.width - 2 and title_start + ti < 80) {
                        buffer[w.y][title_start + ti] = w.title[ti];
                    }
                }
            }
        }
        for (0..24) |y| {
            if (comptime @import("builtin").os.tag != .freestanding) {
                std.debug.print("{s}\n", .{buffer[y][0..80]});
            }
        }
    }
};

fn adapterMain() void {
    runtime.log("compositor: waveguide adapter online");
    const desktop = DesktopEnvironment.init();
    desktop.draw();

    var loops: usize = 0;
    while (loops < 100) : (loops += 1) {
        const event = DisplayPort.Event{ .vsync = .{ .timestamp_ns = @intCast(loops * 16666666) } };
        _ = event;

        var layer1 = [_]u32{0xFF0000FF} ** 16;
        var layer2 = [_]u32{0x00FF007F} ** 16;
        var output = [_]u32{0} ** 16;
        blendLayersSoftware(&layer1, &layer2, &output);
        runtime.yield();
    }
}

pub export fn clarigggz_compositor_entry() callconv(.c) noreturn {
    adapterMain();
    while (true) {
        runtime.yield();
    }
}

pub fn blendLayersSoftware(top: []const u32, bottom: []const u32, output: []u32) void {
    const len = @min(top.len, @min(bottom.len, output.len));
    for (0..len) |i| {
        const c_top = top[i];
        const c_bottom = bottom[i];
        const a_t = c_top & 0xFF;
        const a_b = c_bottom & 0xFF;
        const out_a = a_t + (a_b * (255 - a_t)) / 255;
        if (out_a == 0) {
            output[i] = 0;
            continue;
        }
        const r_t = (c_top >> 24) & 0xFF;
        const g_t = (c_top >> 16) & 0xFF;
        const b_t = (c_top >> 8) & 0xFF;
        const r_b = (c_bottom >> 24) & 0xFF;
        const g_b = (c_bottom >> 16) & 0xFF;
        const b_b = (c_bottom >> 8) & 0xFF;
        const out_r = (r_t * a_t + r_b * a_b * (255 - a_t) / 255) / out_a;
        const out_g = (g_t * a_t + g_b * a_b * (255 - a_t) / 255) / out_a;
        const out_b = (b_t * a_t + b_b * a_b * (255 - a_t) / 255) / out_a;
        output[i] = (@as(u32, @intCast(out_r)) << 24) | (@as(u32, @intCast(out_g)) << 16) | (@as(u32, @intCast(out_b)) << 8) | out_a;
    }
}

const builtin = @import("builtin");
const config = @import("config");

fn startShim() callconv(.c) noreturn {
    clarigggz_compositor_entry();
}

comptime {
    if (builtin.os.tag == .freestanding and !config.kernel_adapter) {
        @export(&startShim, .{ .name = "_start", .linkage = .strong });
    }
}

pub fn main() !void {
    adapterMain();
}
