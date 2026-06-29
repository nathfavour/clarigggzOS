const std = @import("std");
extern fn kernel_alloc(len: u64, align_bytes: u64) ?[*]u8;


/// The types of capabilities supported by the Clarigggz microkernel.
pub const CapType = enum(u8) {
    none = 0,
    memory = 1,    // Access to a range of physical memory
    ipc_endpoint = 2, // Permission to send/receive to a specific port
    irq = 3,       // Permission to handle a specific hardware interrupt
    device = 4,    // Access to MMIO registers for a specific device
    enclave = 5,   // Permission to run/resume a Keystone enclave (object_id = EID)
    keychain_slot = 6, // Permission to open a sealed keychain item (object_id = item_id)
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

    /// Derive a child capability with equal or restricted rights and boundaries.
    pub fn derive(self: Capability, child_rights: u7, sub_base: u64, sub_limit: u32) !Capability {
        // Verify child rights are a strict subset of current rights
        if ((child_rights & self.rights) != child_rights) return error.RightsViolation;

        switch (self.cap_type) {
            .none => return error.InvalidCap,
            .memory, .device => {
                if (sub_base < self.base or sub_base + sub_limit > self.base + self.limit) {
                    return error.OutOfBounds;
                }
                return Capability{
                    .cap_type = self.cap_type,
                    .rights = child_rights,
                    .object_id = self.object_id,
                    .base = sub_base,
                    .limit = sub_limit,
                };
            },
            .ipc_endpoint, .irq, .keychain_slot, .enclave => {
                return Capability{
                    .cap_type = self.cap_type,
                    .rights = child_rights,
                    .object_id = self.object_id,
                    .base = self.base,
                    .limit = self.limit,
                };
            },
        }
    }
};

/// A CList is a collection of capabilities owned by a specific thread or process.
pub const CList = struct {
    caps: []Capability,
    owner_id: u32,

    pub fn init(out: *CList, comptime max_caps: usize, owner: u32) void {
        const print = @import("main.zig").printString;
        print("    [CList.init] Start\n");
        const byte_count = comptime max_caps * @sizeOf(Capability);
        print("    [CList.init] Allocating...\n");
        const raw = kernel_alloc(byte_count, @alignOf(Capability)) orelse {
            print("[Panic] Out of memory allocating CList!\n");
            while (true) {}
        };
        print("    [CList.init] Allocated!\n");
        const caps = @as([*]Capability, @ptrCast(@alignCast(raw)))[0..max_caps];
        print("    [CList.init] Memsetting...\n");
        @memset(caps, Capability{
            .cap_type = .none,
            .rights = 0,
            .object_id = 0,
            .base = 0,
            .limit = 0,
        });
        print("    [CList.init] Writing to out...\n");
        out.* = CList{
            .caps = caps,
            .owner_id = owner,
        };
        print("    [CList.init] End\n");
    }

    pub fn initTest(out: *CList, allocator: std.mem.Allocator, max_caps: usize, owner: u32) void {
        const caps = allocator.alloc(Capability, max_caps) catch {
            @panic("Out of memory allocating CList");
        };
        @memset(caps, Capability{
            .cap_type = .none,
            .rights = 0,
            .object_id = 0,
            .base = 0,
            .limit = 0,
        });
        out.* = CList{
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

    /// Grant a capability to another CList. Requires the 'grant' right.
    pub fn grant(self: *CList, src_idx: usize, dest_clist: *CList, dest_idx: usize) !void {
        const cap = self.get(src_idx) orelse return error.InvalidSourceCapability;
        if ((cap.rights & Capability.Rights.grant) == 0) return error.NoGrantPermission;

        if (dest_idx >= dest_clist.caps.len) return error.IndexOutOfBounds;
        if (dest_clist.caps[dest_idx].cap_type != .none) return error.DestinationSlotBusy;

        dest_clist.caps[dest_idx] = cap;
    }

    /// Revoke a capability from the CList.
    pub fn revoke(self: *CList, index: usize) !void {
        if (index >= self.caps.len) return error.IndexOutOfBounds;
        self.caps[index] = Capability{
            .cap_type = .none,
            .rights = 0,
            .object_id = 0,
            .base = 0,
            .limit = 0,
        };
    }

    /// Validate that a capability exists, has the expected type, and meets required rights.
    pub fn validate(self: *const CList, index: usize, expected_type: CapType, required_rights: u7) !Capability {
        const cap = self.get(index) orelse return error.InvalidCapability;
        if (cap.cap_type != expected_type) return error.WrongCapType;
        if ((cap.rights & required_rights) != required_rights) return error.NoPermission;
        return cap;
    }
};

test "Capability System - Derivation, Grant, Validation, and Revocation" {
    const allocator = std.testing.allocator;

    var clist_a: CList = undefined;
    CList.initTest(&clist_a, allocator, 8, 1);
    defer allocator.free(clist_a.caps);

    var clist_b: CList = undefined;
    CList.initTest(&clist_b, allocator, 8, 2);
    defer allocator.free(clist_b.caps);

    // Setup memory capability in A
    clist_a.caps[0] = .{
        .cap_type = .memory,
        .rights = Capability.Rights.read | Capability.Rights.write | Capability.Rights.grant,
        .object_id = 0,
        .base = 0x1000,
        .limit = 0x1000,
    };

    // Derive a restricted capability
    const derived = try clist_a.caps[0].derive(Capability.Rights.read, 0x1100, 0x100);
    try std.testing.expectEqual(derived.cap_type, CapType.memory);
    try std.testing.expectEqual(derived.rights, Capability.Rights.read);
    try std.testing.expectEqual(derived.base, 0x1100);
    try std.testing.expectEqual(derived.limit, 0x100);

    // Fail derivation with excessive rights
    try std.testing.expectError(error.RightsViolation, clist_a.caps[0].derive(Capability.Rights.execute, 0x1000, 0x100));

    // Grant capability from A to B
    try clist_a.grant(0, &clist_b, 0);
    try std.testing.expectEqual(clist_b.caps[0].cap_type, CapType.memory);

    // Validate capability in B
    const validated = try clist_b.validate(0, .memory, Capability.Rights.read | Capability.Rights.write);
    try std.testing.expectEqual(validated.base, 0x1000);

    // Revoke capability
    try clist_b.revoke(0);
    try std.testing.expect(clist_b.get(0) == null);
}
