const std = @import("std");
const capability = @import("capability.zig");
const paging = @import("paging.zig");

/// RISC-V 64-bit Register Context
pub const Context = struct {
    // General Purpose Registers (saved/restored during switch)
    ra: u64 = 0,
    sp: u64 = 0,
    s: [12]u64 = [_]u64{0} ** 12, // s0 - s11 (callee-saved)
    
    // CSRs
    mstatus: u64 = 0,
    mepc: u64 = 0,
    satp: u64 = 0, // Page Table Root

    // Vector Status (RVV 1.0)
    vtype: u64 = 0,
    vl: u64 = 0,
    vstart: u64 = 0,
    // Note: Actual vector registers (v0-v31) are saved separately 
    // to avoid massive overhead for non-vector threads.
};

pub const ThreadState = enum {
    ready,
    running,
    blocked,
    terminated,
};

pub const Thread = struct {
    id: u32,
    state: ThreadState,
    context: Context,
    clist: *capability.CList,
    aspace: ?paging.AddressSpace = null, // Isolated Virtual Memory
    stack_base: usize,
    stack_size: usize,
    
    // RVV Mastery: Track if this thread has used vector instructions
    // to optimize context switch overhead.
    uses_vectors: bool = false,

    pub fn init(id: u32, clist: *capability.CList, aspace: ?paging.AddressSpace, stack_ptr: usize, entry_point: usize) Thread {
        var ctx = Context{};
        ctx.sp = stack_ptr;
        ctx.mepc = entry_point;
        if (aspace) |as| {
            ctx.satp = as.satp();
        }
        // Set mstatus.MPP = 01 (Supervisor) or 00 (User) and enable interrupts (MPIE)
        ctx.mstatus = 0x00001880; 

        return .{
            .id = id,
            .state = .ready,
            .context = ctx,
            .clist = clist,
            .aspace = aspace,
            .stack_base = stack_ptr - 4096, // Simplified stack tracking
            .stack_size = 4096,
        };
    }
};

pub const Scheduler = struct {
    threads: std.ArrayList(*Thread),
    current_idx: usize = 0,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Scheduler {
        return .{
            .threads = std.ArrayList(*Thread).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn addThread(self: *Scheduler, thread: *Thread) !void {
        try self.threads.append(thread);
    }

    /// Basic Round-Robin Scheduler for the Core Broker.
    pub fn schedule(self: *Scheduler) ?*Thread {
        if (self.threads.items.len == 0) return null;
        
        // Simple RR logic
        self.current_idx = (self.current_idx + 1) % self.threads.items.len;
        const next = self.threads.items[self.current_idx];
        
        if (next.state == .ready or next.state == .running) {
            next.state = .running;
            return next;
        }
        
        return null;
    }
};
