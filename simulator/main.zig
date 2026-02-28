const std = @import("std");
const protocols = @import("protocols");
const Message = protocols.ipc.Message;

// The simulator needs to pull in the core logic to mock the kernel on x86_64
const capability = @import("../core/capability.zig");
const ipc_transport = @import("../core/ipc_transport.zig");

const mmio = @import("mmio.zig");
const irq_controller = @import("irq_controller.zig");

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

    // 2. Initialize Digital Twin Mocks
    var mock_mmio = mmio.MMIO.init(allocator);
    defer mock_mmio.deinit();

    var mock_irqc = try irq_controller.IRQController.init(allocator, 1024);
    defer mock_irqc.deinit();

    // 3. Initialize a Mock Process (e.g., Tactile ID Adapter)
    var tactile_clist = try capability.CList.init(allocator, 16, 200);
    defer allocator.free(tactile_clist.caps);

    const tactile_port = try router.createPort(200, &tactile_clist);
    std.debug.print("Created Tactile Port: {}\n", .{tactile_port});

    // 4. Simulated Event Loop
    std.debug.print("Simulator active. Digital Twin established.\n", .{});

    // Trigger a simulated tactile sensor interrupt (IRQ 7)
    mock_irqc.raise(7);

    // 5. Dispatch Loop: Core Broker checks for interrupts
    if (mock_irqc.claim()) |irq| {
        std.debug.print("Core Broker: Servicing IRQ {} from simulated hardware.\n", .{irq});
        
        // Example: Push an IPC event to the Tactile ID adapter in response to IRQ
        const msg = Message{
            .sender_id = 0, // From Kernel
            .protocol_id = 0xCAF2, // InputPort
            .payload_len = 0,
            .capability_bits = 0,
            .payload = [_]u8{0} ** 128,
        };
        const port = router.ports.get(tactile_port).?;
        try port.push(msg);

        mock_irqc.complete(irq);
    }

    // 6. Adapter Processes Message
    const port = router.ports.get(tactile_port).?;
    if (port.pop()) |delivered| {
        std.debug.print("Tactile Adapter: Message received, protocol=0x{X}\n", .{delivered.protocol_id});
    }

    std.debug.print("Simulation complete.\n", .{});
}
