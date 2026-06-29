const std = @import("std");
const builtin = @import("builtin");

/// QEMU virt PLIC (Platform-Level Interrupt Controller).
pub const Plic = struct {
    base: u64,

  pub const qemu_virt_base: u64 = 0x0c000000;
    pub const spacemit_k1_base: u64 = 0x04000000;

    pub const IRQ_UART: u32 = 10;
    pub const IRQ_TACTILE: u32 = 7;
    pub const IRQ_VSYNC: u32 = 1;
    pub const IRQ_AGENT: u32 = 16;

    pub fn init(base: u64) Plic {
        return .{ .base = base };
    }

    inline fn reg(self: Plic, offset: u64) *volatile u32 {
        return @ptrFromInt(self.base + offset);
    }

    pub fn enable(self: *const Plic, ctx: u32, irq: u32) void {
        if (comptime builtin.os.tag != .freestanding) return;
        const enable_word = self.reg(0x2000 + ctx * 0x80 + (irq / 32) * 4);
        enable_word.* |= @as(u32, 1) << @intCast(irq % 32);
        const threshold = self.reg(0x200000 + ctx * 0x1000);
        threshold.* = 0;
    }

    pub fn claim(self: *const Plic, ctx: u32) ?u32 {
        if (comptime builtin.os.tag != .freestanding) return null;
        const claim_reg = self.reg(0x200004 + ctx * 0x1000);
        const irq = claim_reg.*;
        if (irq == 0) return null;
        return irq;
    }

    pub fn complete(self: *const Plic, ctx: u32, irq: u32) void {
        if (comptime builtin.os.tag != .freestanding) return;
        const complete_reg = self.reg(0x200004 + ctx * 0x1000);
        complete_reg.* = irq;
    }

    pub fn setPriority(self: *const Plic, irq: u32, priority: u32) void {
        if (comptime builtin.os.tag != .freestanding) return;
        const prio = self.reg(4 + irq * 4);
        prio.* = priority;
    }
};

/// RISC-V CLINT (timer for VSync cadence).
pub const Clint = struct {
    base: u64,

    pub const qemu_virt_base: u64 = 0x02000000;

    pub fn init(base: u64) Clint {
        return .{ .base = base };
    }

    inline fn mtime(self: Clint) *volatile u64 {
        return @ptrFromInt(self.base + 0xBFF8);
    }

    inline fn mtimecmp(self: Clint, hart: u32) *volatile u64 {
        return @ptrFromInt(self.base + 0x4000 + hart * 8);
    }

    pub fn readTime(self: Clint) u64 {
        if (comptime builtin.os.tag != .freestanding) return 0;
        return self.mtime().*;
    }

    pub fn armTimer(self: *const Clint, hart: u32, delta: u64) void {
        if (comptime builtin.os.tag != .freestanding) return;
        self.mtimecmp(hart).* = self.mtime().* + delta;
    }
};
