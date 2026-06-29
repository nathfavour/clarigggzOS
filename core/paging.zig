const std = @import("std");
const builtin = @import("builtin");

extern fn kernel_alloc(len: u64, align_bytes: u64) ?[*]u8;

/// SV39 Page Table Entry (PTE) for RISC-V 64-bit.
pub const PTE = packed struct(u64) {
    v: bool,      // Valid
    r: bool,      // Read
    w: bool,      // Write
    x: bool,      // Execute
    u: bool,      // User-accessible
    g: bool,      // Global
    a: bool,      // Accessed
    d: bool,      // Dirty
    rsw: u2 = 0,  // Reserved for software
    ppn: u44,     // Physical Page Number
    reserved: u10 = 0,

    pub const Flags = struct {
        pub const valid: u8 = 1 << 0;
        pub const read: u8 = 1 << 1;
        pub const write: u8 = 1 << 2;
        pub const exec: u8 = 1 << 3;
        pub const user: u8 = 1 << 4;
        pub const accessed: u8 = 1 << 5;
        pub const dirty: u8 = 1 << 6;
    };

    pub fn isLeaf(self: PTE) bool {
        return self.r or self.w or self.x;
    }
};

/// An Address Space manages the three-level SV39 page table for a process.
pub const AddressSpace = struct {
    root_page_table: [*]PTE,
    allocator: std.mem.Allocator,

    pub const PageSize = 4096;

    pub fn init(allocator: std.mem.Allocator) !AddressSpace {
        if (comptime builtin.is_test) {
            const table = try allocator.alloc(PTE, 512);
            @memset(table, @bitCast(@as(u64, 0)));
            return .{
                .root_page_table = table.ptr,
                .allocator = allocator,
            };
        }
        var space: AddressSpace = undefined;
        paging_init(&space, allocator.ptr, allocator.vtable);
        return space;
    }

    /// Recursively free all non-leaf page tables under a page table directory.
    fn freePageTable(self: *AddressSpace, table: [*]PTE, level: usize) void {
        if (level == 0) return;
        for (0..512) |i| {
            const pte = table[i];
            if (pte.v and !pte.isLeaf()) {
                const sub_table: [*]PTE = @ptrFromInt(@as(u64, pte.ppn) << 12);
                self.freePageTable(sub_table, level - 1);
                const slice: []PTE = sub_table[0..512];
                self.allocator.free(slice);
            }
        }
    }

    pub fn deinit(self: *AddressSpace) void {
        self.freePageTable(self.root_page_table, 2);
        const slice: []PTE = self.root_page_table[0..512];
        self.allocator.free(slice);
    }

    /// Extract Virtual Page Number (VPN) index for a given level (0, 1, 2)
    inline fn getVpn(va: u64, level: usize) usize {
        return @intCast((va >> @intCast(12 + level * 9)) & 0x1FF);
    }

    /// Helper to get or allocate a child page table
    fn getOrAllocNextLevel(self: *AddressSpace, parent_pte: *PTE) ![*]PTE {
        if (parent_pte.v) {
            if (parent_pte.isLeaf()) return error.PteIsLeaf;
            return @ptrFromInt(@as(u64, parent_pte.ppn) << 12);
        }

        const new_table = if (comptime builtin.is_test) blk: {
            const table = try self.allocator.alloc(PTE, 512);
            @memset(table, @bitCast(@as(u64, 0)));
            break :blk table;
        } else blk: {
            const raw_ptr = kernel_alloc(512 * @sizeOf(PTE), 4096) orelse return error.OutOfMemory;
            break :blk @as([*]PTE, @ptrCast(@alignCast(raw_ptr)))[0..512];
        };

        parent_pte.* = .{
            .v = true,
            .r = false,
            .w = false,
            .x = false,
            .u = false,
            .g = false,
            .a = false,
            .d = false,
            .ppn = @intCast(@intFromPtr(new_table.ptr) >> 12),
        };

        return new_table.ptr;
    }

    /// Map a virtual page to a physical page with specific flags.
    pub fn map(self: *AddressSpace, va: u64, pa: u64, flags: u8) !void {
        if (va % PageSize != 0 or pa % PageSize != 0) return error.AddressNotAligned;

        const vpn2 = getVpn(va, 2);
        const vpn1 = getVpn(va, 1);
        const vpn0 = getVpn(va, 0);

        const lvl1_table = try self.getOrAllocNextLevel(&self.root_page_table[vpn2]);
        const lvl0_table = try self.getOrAllocNextLevel(&lvl1_table[vpn1]);

        const pte = &lvl0_table[vpn0];
        if (pte.v) return error.AlreadyMapped;

        pte.* = .{
            .v = (flags & PTE.Flags.valid) != 0,
            .r = (flags & PTE.Flags.read) != 0,
            .w = (flags & PTE.Flags.write) != 0,
            .x = (flags & PTE.Flags.exec) != 0,
            .u = (flags & PTE.Flags.user) != 0,
            .g = false,
            .a = (flags & PTE.Flags.accessed) != 0,
            .d = (flags & PTE.Flags.dirty) != 0,
            .ppn = @intCast(pa >> 12),
        };
    }

    /// Unmap a virtual page address.
    pub fn unmap(self: *AddressSpace, va: u64) !void {
        if (va % PageSize != 0) return error.AddressNotAligned;

        const vpn2 = getVpn(va, 2);
        const vpn1 = getVpn(va, 1);
        const vpn0 = getVpn(va, 0);

        if (!self.root_page_table[vpn2].v) return error.NotMapped;
        const lvl1_table: [*]PTE = @ptrFromInt(@as(u64, self.root_page_table[vpn2].ppn) << 12);

        if (!lvl1_table[vpn1].v) return error.NotMapped;
        const lvl0_table: [*]PTE = @ptrFromInt(@as(u64, lvl1_table[vpn1].ppn) << 12);

        const pte = &lvl0_table[vpn0];
        if (!pte.v) return error.NotMapped;

        pte.* = @bitCast(@as(u64, 0));
    }

    /// Translate a virtual address to its corresponding physical address.
    pub fn translate(self: *const AddressSpace, va: u64) ?u64 {
        const offset = va & 0xFFF;
        const vpn2 = getVpn(va, 2);
        const vpn1 = getVpn(va, 1);
        const vpn0 = getVpn(va, 0);

        const pte2 = self.root_page_table[vpn2];
        if (!pte2.v) return null;
        if (pte2.isLeaf()) {
            // Mega-page mapping (1GB)
            const pa = (@as(u64, pte2.ppn) << 12) + (va & 0x3FFFFFFF);
            return pa;
        }

        const lvl1_table: [*]PTE = @ptrFromInt(@as(u64, pte2.ppn) << 12);
        const pte1 = lvl1_table[vpn1];
        if (!pte1.v) return null;
        if (pte1.isLeaf()) {
            // Huge-page mapping (2MB)
            const pa = (@as(u64, pte1.ppn) << 12) + (va & 0x1FFFFF);
            return pa;
        }

        const lvl0_table: [*]PTE = @ptrFromInt(@as(u64, pte1.ppn) << 12);
        const pte0 = lvl0_table[vpn0];
        if (!pte0.v) return null;

        return (@as(u64, pte0.ppn) << 12) | offset;
    }

    /// Generate the value for the 'satp' (Supervisor Address Translation and Protection) CSR.
    pub fn satp(self: *const AddressSpace) u64 {
        const ppn = @intFromPtr(self.root_page_table) >> 12;
        const mode: u64 = 8; // SV39 Mode
        return (mode << 60) | ppn;
    }
};

pub export fn paging_init(out: *AddressSpace, allocator_ptr: *anyopaque, allocator_vtable: *const std.mem.Allocator.VTable) void {
    const raw_ptr = kernel_alloc(512 * @sizeOf(PTE), 4096) orelse {
        const print = @import("main.zig").printString;
        print("[Panic] Out of memory allocating root page table!\n");
        while (true) {}
    };
    const ptr = @as([*]PTE, @ptrCast(@alignCast(raw_ptr)))[0..512];
    @memset(ptr, @bitCast(@as(u64, 0)));
    out.* = AddressSpace{
        .root_page_table = ptr.ptr,
        .allocator = .{
            .ptr = allocator_ptr,
            .vtable = allocator_vtable,
        },
    };
}

test "SV39 Paging - Map, Translate, Unmap" {
    const allocator = std.testing.allocator;
    var aspace = try AddressSpace.init(allocator);
    defer aspace.deinit();

    // Map a test page
    const va = 0x10000;
    const pa = 0x80000000;
    const flags = PTE.Flags.valid | PTE.Flags.read | PTE.Flags.write | PTE.Flags.user;

    try aspace.map(va, pa, flags);

    // Verify translation
    const trans = aspace.translate(va + 0x123);
    try std.testing.expectEqual(trans.?, pa + 0x123);

    // Unmap the page
    try aspace.unmap(va);
    try std.testing.expect(aspace.translate(va) == null);
}
