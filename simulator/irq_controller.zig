const std = @import("std");

/// Mock Interrupt Controller for the Clarigggz Simulator.
/// Simulates the K1's PLIC/CLINT behavior for user-space simulation.
pub const IRQController = struct {
    pending_irqs: std.DynamicBitSet,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, max_irqs: usize) !IRQController {
        return .{
            .pending_irqs = try std.DynamicBitSet.initEmpty(allocator, max_irqs),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *IRQController) void {
        self.pending_irqs.deinit();
    }

    /// Raise a simulated interrupt (e.g., from a mock camera or tactile sensor).
    pub fn raise(self: *IRQController, irq: usize) void {
        if (irq < self.pending_irqs.capacity()) {
            self.pending_irqs.set(irq);
            // std.debug.print("[Simulator IRQ] Raised IRQ: {}
", .{irq});
        }
    }

    /// Claim the highest priority pending interrupt.
    pub fn claim(self: *IRQController) ?usize {
        return self.pending_irqs.findFirstSet();
    }

    /// Acknowledge (clear) a handled interrupt.
    pub fn complete(self: *IRQController, irq: usize) void {
        if (irq < self.pending_irqs.capacity()) {
            self.pending_irqs.unset(irq);
        }
    }
};
