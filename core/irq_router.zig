const std = @import("std");
const protocols = @import("protocols");
const ipc_transport = @import("ipc_transport.zig");
const plic = @import("plic.zig");

pub const IrqBinding = struct {
    irq: u32,
    port_id: u32,
    protocol_id: u32,
};

pub const IrqRouter = struct {
    bindings: [32]IrqBinding,
    binding_count: usize = 0,
    plic_dev: plic.Plic,
    vsync_count: u64 = 0,

    pub fn init(plic_base: u64) IrqRouter {
        var router = IrqRouter{
            .bindings = undefined,
            .plic_dev = plic.Plic.init(plic_base),
        };
        router.plic_dev.setPriority(plic.Plic.IRQ_UART, 1);
        router.plic_dev.setPriority(plic.Plic.IRQ_TACTILE, 3);
        router.plic_dev.setPriority(plic.Plic.IRQ_VSYNC, 5);
        router.plic_dev.setPriority(plic.Plic.IRQ_AGENT, 2);
        router.plic_dev.enable(0, plic.Plic.IRQ_UART);
        router.plic_dev.enable(0, plic.Plic.IRQ_TACTILE);
        router.plic_dev.enable(0, plic.Plic.IRQ_VSYNC);
        router.plic_dev.enable(0, plic.Plic.IRQ_AGENT);
        return router;
    }

    pub fn bind(self: *IrqRouter, irq: u32, port_id: u32, protocol_id: u32) !void {
        if (self.binding_count >= self.bindings.len) return error.TooManyBindings;
        self.bindings[self.binding_count] = .{
            .irq = irq,
            .port_id = port_id,
            .protocol_id = protocol_id,
        };
        self.binding_count += 1;
    }

    pub fn dispatchPending(
        self: *IrqRouter,
        ipc: *ipc_transport.Router,
        sched: *@import("scheduler.zig").Scheduler,
        on_agent_irq: ?*const fn () void,
    ) void {
        while (self.plic_dev.claim(0)) |irq| {
            self.handleIrq(irq, ipc, sched, on_agent_irq);
            self.plic_dev.complete(0, irq);
        }
    }

    fn handleIrq(
        self: *IrqRouter,
        irq: u32,
        ipc: *ipc_transport.Router,
        sched: *@import("scheduler.zig").Scheduler,
        on_agent_irq: ?*const fn () void,
    ) void {
        if (irq == plic.Plic.IRQ_AGENT) {
            if (on_agent_irq) |cb| cb();
        }

        if (irq == plic.Plic.IRQ_VSYNC) self.vsync_count += 1;

        for (self.bindings[0..self.binding_count]) |binding| {
            if (binding.irq != irq) continue;
            if (binding.port_id >= ipc.ports.len) continue;
            const port = ipc.ports[binding.port_id] orelse continue;

            const msg = protocols.ipc.Message{
                .sender_id = 0,
                .protocol_id = binding.protocol_id,
                .payload_len = @sizeOf(u32),
                .capability_bits = 0,
                .payload = blk: {
                    var p: [128]u8 = undefined;
                    @memcpy(p[0..4], std.mem.asBytes(&irq));
                    break :blk p;
                },
            };
            port.push(msg) catch continue;
            sched.unblockThreadsWaitingOn(.ipc_recv, binding.port_id);
            break;
        }
    }
};
