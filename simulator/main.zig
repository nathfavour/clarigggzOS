const std = @import("std");
const protocols = @import("protocols");
const Message = protocols.ipc.Message;

// The simulator needs to pull in the core logic to mock the kernel on x86_64
const capability = @import("../core/capability.zig");
const ipc_transport = @import("../core/ipc_transport.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n--- Clarigggz OS Simulator (x86_64-linux) ---\n", .{});

    // 1. Initialize Simulator Core Broker
    var router = ipc_transport.Router.init(allocator);
    defer {
        var it = router.ports.iterator();
        while (it.next()) |entry| {
            allocator.destroy(entry.value_ptr.*);
        }
        router.ports.deinit();
    }

    // 2. Initialize a Mock Process (e.g., Camera Adapter)
    var camera_clist = try capability.CList.init(allocator, 16, 100);
    defer allocator.free(camera_clist.caps);

    const camera_port = try router.createPort(100, &camera_clist);
    std.debug.print("Created Camera Port: {}\n", .{camera_port});

    // 3. Simulated Event Loop
    std.debug.print("Simulator active. Processing mock frames...\n", .{});

    // Example: Push a simulated frame event
    const msg = Message{
        .sender_id = 100,
        .protocol_id = 0xCAF1, // Mock DisplayPort Protocol
        .payload_len = 0,
        .capability_bits = 0,
        .payload = [_]u8{0} ** 128,
    };

    const port = router.ports.get(camera_port).?;
    try port.push(msg);

    // 4. Dispatch simulated messages
    if (port.pop()) |delivered| {
        std.debug.print("Message dispatched: protocol=0x{X}\n", .{delivered.protocol_id});
    }

    std.debug.print("Simulation complete.\n", .{});
}
