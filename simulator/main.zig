const std = @import("std");
const protocols = @import("protocols");
const Message = protocols.ipc.Message;

const core = @import("core");
const capability = core.capability;
const ipc_transport = core.ipc_transport;

const mmio = @import("mmio.zig");
const irq_controller = @import("irq_controller.zig");
const compositor = @import("compositor");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    core.printString("\n");
    core.printCentered("================================================================================", 80);
    core.printCentered("______ _            _                             ____   _____", 80);
    core.printCentered("/ ____/| |          (_)                           / __ \\ / ____|", 80);
    core.printCentered("| |     | | __ _ _ __ _  __ _  __ _  __ _ ____    | |  | | (___  ", 80);
    core.printCentered("| |     | |/ _` | '__| |/ _` |/ _` |/ _` |_  /    | |  | |\\___ \\ ", 80);
    core.printCentered("| |____ | | (_| | |  | | (_| | (_| | (_| |/ /     | |__| |____) |", 80);
    core.printCentered("\\_____/|_|\\__,_|_|  |_|\\__, |\\__, |\\__, /___|     \\____/|_____/ ", 80);
    core.printCentered("                        __/ | __/ | __/ |                       ", 80);
    core.printCentered("                       |___/ |___/ |___/                        ", 80);
    core.printCentered("================================================================================", 80);
    core.printCentered("The Agent-Native Sovereign OS | RISC-V 64 Hexagonal Microkernel", 80);
    core.printCentered("Booting Kernel version 0.1.0 ... (Simulation Mode)", 80);
    core.printString("\n");

    std.debug.print("--- Clarigggz OS Simulator (x86_64-linux) ---\n", .{});

    core.rvv.init();
    core.rvv.logStatus(core.printString);

    var router = ipc_transport.Router.init(allocator);
    defer {
        for (router.ports[0..router.ports_count]) |maybe_port| {
            if (maybe_port) |port| {
                allocator.destroy(port);
            }
        }
    }

    var mock_mmio = mmio.MMIO.init(allocator);
    defer mock_mmio.deinit();

    var mock_irqc = try irq_controller.IRQController.init(allocator, 1024);
    defer mock_irqc.deinit();

    var tactile_clist: capability.CList = undefined;
    capability.CList.initTest(&tactile_clist, allocator, 16, 200);
    defer allocator.free(tactile_clist.caps);

    const tactile_port = try router.createPort(200, &tactile_clist);
    std.debug.print("Created Tactile Port: {}\n", .{tactile_port});

    std.debug.print("Simulator active. Digital Twin established.\n", .{});

    mock_irqc.raise(7);

    if (mock_irqc.claim()) |irq| {
        std.debug.print("Core Broker: Servicing IRQ {} from simulated hardware.\n", .{irq});

        const msg = Message{
            .sender_id = 0,
            .protocol_id = 0xCAF2,
            .payload_len = 0,
            .capability_bits = 0,
            .payload = [_]u8{0} ** 128,
        };
        const port = router.ports[tactile_port].?;
        try port.push(msg);
        mock_irqc.complete(irq);
    }

    if (router.ports[tactile_port].?.pop()) |delivered| {
        std.debug.print("Tactile Adapter: Message received, protocol=0x{X}\n", .{delivered.protocol_id});
    }

    std.debug.print("\n--- Clarigggz Keychain (TEE stub) ---\n", .{});
    var keychain = core.tee_mod.initKeychain();
    const passkey_id = try keychain.storePasskey("glasses.local", &[_]u8{ 0xC0, 0xFF, 0xEE });
    std.debug.print("Stored passkey item id={}\n", .{passkey_id});
    std.debug.print("TEE backend: {s}\n", .{@tagName(keychain.backendKind())});

    std.debug.print("\n--- Security: Intent-to-Unlock Pipeline ---\n", .{});
    var security_mgr = core.security.SecurityManager{};
    var tap_verifier = core.physical_intent.PhysicalSequenceVerifier{};
    const unlock_seq = [_]struct { u16, u64, bool }{
        .{ 1, 100, false },
        .{ 3, 200, false },
        .{ 2, 300, false },
        .{ 4, 400, true },
    };
    for (unlock_seq) |step| {
        security_mgr.handleTactileEvent(&tap_verifier, step[0], step[1], step[2], struct {
            fn emit(msg: []const u8) void {
                std.debug.print("{s}", .{msg});
            }
        }.emit);
    }
    std.debug.print("Security state: {s}\n", .{@tagName(security_mgr.state)});

    std.debug.print("\n--- Secure Enclave (legacy path via keychain) ---\n", .{});
    keychain.appendLiability("SIM: liability shift recorded");
    _ = try keychain.storeBiometricTemplate("tactile-id", &[_]u8{ 0xDE, 0xAD, 0xBE, 0xEF });
    std.debug.print("Keychain items sealed: {}\n", .{keychain.item_count});

    std.debug.print("\n--- Agent Runtime ---\n", .{});
    var agent_rt = core.agent_runtime_mod.AgentRuntime.init();
    const planner_id = try agent_rt.register("spatial-planner", 4, 0);
    const vision_id = try agent_rt.register("vision-agent", 6, 0);
    std.debug.print("Registered agents: planner={}, vision={}\n", .{ planner_id, vision_id });
    agent_rt.tick();
    std.debug.print("Agent tick count: {}\n", .{agent_rt.tick_count});

    std.debug.print("\n--- Waveguide Framebuffer ---\n", .{});
    var fb = core.framebuffer_mod.Framebuffer.init(core.framebuffer_mod.Framebuffer.default_base);
    const info = fb.info();
    std.debug.print("Framebuffer {}x{} @ 0x{x}\n", .{ info.width, info.height, info.base_addr });
    _ = fb.signalVsync();

    std.debug.print("\n--- Display Environment: Loading Desktop ---\n", .{});
    const desktop = compositor.DesktopEnvironment.init();
    desktop.draw();

    std.debug.print("\nSimulation complete.\n", .{});
}
