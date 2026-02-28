const std = @import("std");

/// The types of capabilities supported by the Clarigggz microkernel.
pub const CapType = enum(u8) {
    none = 0,
    memory = 1,    // Access to a range of physical memory
    ipc_endpoint = 2, // Permission to send/receive to a specific port
    irq = 3,       // Permission to handle a specific hardware interrupt
    device = 4,    // Access to MMIO registers for a specific device
};

/// A single Capability entry. 128 bits total for cache-line alignment and speed.
pub const Capability = struct {
    cap_type: CapType,
    rights: u7,        // Read, Write, Execute, Grant, etc.
    object_id: u24,    // ID of the target object (e.g., Port ID, IRQ number)
    
    // Address range or specific data depending on CapType
    base: u64,         
    limit: u32,

    pub const Rights = struct {
        pub const read: u7 = 1 << 0;
        pub const write: u7 = 1 << 1;
        pub const execute: u7 = 1 << 2;
        pub const grant: u7 = 1 << 3; // Right to pass this cap to another process
    };
};

/// A CList is a collection of capabilities owned by a specific thread or process.
pub const CList = struct {
    caps: []Capability,
    owner_id: u32,

    pub fn init(allocator: std.mem.Allocator, max_caps: usize, owner: u32) !CList {
        const caps = try allocator.alloc(Capability, max_caps);
        @memset(caps, Capability{
            .cap_type = .none,
            .rights = 0,
            .object_id = 0,
            .base = 0,
            .limit = 0,
        });
        return CList{
            .caps = caps,
            .owner_id = owner,
        };
    }

    pub fn get(self: *const CList, index: usize) ?Capability {
        if (index >= self.caps.len) return null;
        const cap = self.caps[index];
        if (cap.cap_type == .none) return null;
        return cap;
    }
};
