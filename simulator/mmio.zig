const std = @import("std");

/// Mock Memory-Mapped I/O for the Clarigggz Simulator.
/// Simulates the Spacemit K1's peripheral register space.
pub const MMIO = struct {
    registers: std.AutoHashMap(u64, u32),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MMIO {
        return .{
            .registers = std.AutoHashMap(u64, u32).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MMIO) void {
        self.registers.deinit();
    }

    pub fn read32(self: *MMIO, address: u64) u32 {
        return self.registers.get(address) orelse 0;
    }

    pub fn write32(self: *MMIO, address: u64, value: u32) !void {
        try self.registers.put(address, value);
        // std.debug.print("[Simulator MMIO] Write to 0x{X}: 0x{X}
", .{address, value});
    }
};
