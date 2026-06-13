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

pub const WaitReason = enum {
    none,
    ipc_send,
    ipc_recv,
    interrupt,
};

pub const Thread = struct {
    id: u32,
    state: ThreadState,
    context: Context,
    clist: *capability.CList,
    aspace: ?paging.AddressSpace = null, // Isolated Virtual Memory
    stack_base: usize,
    stack_size: usize,
    priority: u8 = 2, // 0 (highest) to 3 (lowest/idle)
    wait_reason: WaitReason = .none,
    wait_object_id: u64 = 0,
    
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

    pub fn block(self: *Thread, reason: WaitReason, object_id: u64) void {
        self.state = .blocked;
        self.wait_reason = reason;
        self.wait_object_id = object_id;
    }

    pub fn unblock(self: *Thread) void {
        self.state = .ready;
        self.wait_reason = .none;
        self.wait_object_id = 0;
    }
};

pub const Scheduler = struct {
    threads: std.ArrayList(*Thread),
    current_idx: usize = 0,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Scheduler {
        return .{
            .threads = .empty,
            .allocator = allocator,
        };
    }

    pub fn addThread(self: *Scheduler, thread: *Thread) !void {
        try self.threads.append(self.allocator, thread);
    }

    pub fn deinit(self: *Scheduler) void {
        self.threads.deinit(self.allocator);
    }

    /// Priority-based scheduling. Schedules the highest priority ready thread.
    pub fn schedule(self: *Scheduler) ?*Thread {
        if (self.threads.items.len == 0) return null;

        var selected_thread: ?*Thread = null;
        var best_prio: u8 = 255;
        var best_idx: ?usize = null;

        // Iterate through all threads to find the highest priority ready thread
        // For round-robin behavior within same priority, we start search from current_idx + 1
        const count = self.threads.items.len;
        const start_idx = self.current_idx;
        var i: usize = 0;
        while (i < count) : (i += 1) {
            const idx = (start_idx + 1 + i) % count;
            const t = self.threads.items[idx];
            if (t.state == .ready or t.state == .running) {
                if (t.priority < best_prio) {
                    best_prio = t.priority;
                    selected_thread = t;
                    best_idx = idx;
                }
            }
        }

        if (selected_thread) |t| {
            if (best_idx) |idx| {
                self.current_idx = idx;
            }
            // If the previously running thread is still running, set it to ready
            for (self.threads.items) |other| {
                if (other.id != t.id and other.state == .running) {
                    other.state = .ready;
                }
            }
            t.state = .running;
            return t;
        }

        return null;
    }

    pub fn getCurrentThread(self: *const Scheduler) ?*Thread {
        for (self.threads.items) |t| {
            if (t.state == .running) return t;
        }
        return null;
    }

    /// Block a thread with a specific reason.
    pub fn blockThread(self: *Scheduler, thread_id: u32, reason: WaitReason, object_id: u64) void {
        for (self.threads.items) |t| {
            if (t.id == thread_id) {
                t.block(reason, object_id);
                break;
            }
        }
    }

    /// Unblock a thread by its ID.
    pub fn unblockThread(self: *Scheduler, thread_id: u32) void {
        for (self.threads.items) |t| {
            if (t.id == thread_id) {
                t.unblock();
                break;
            }
        }
    }

    /// Unblock all threads waiting on a specific reason and object.
    pub fn unblockThreadsWaitingOn(self: *Scheduler, reason: WaitReason, object_id: u64) void {
        for (self.threads.items) |t| {
            if (t.state == .blocked and t.wait_reason == reason and t.wait_object_id == object_id) {
                t.unblock();
            }
        }
    }
};

test "Scheduler - Priority Scheduling and Blocking" {
    const allocator = std.testing.allocator;

    var sched = Scheduler.init(allocator);
    defer sched.deinit();

    var clist = try capability.CList.init(allocator, 4, 1);
    defer allocator.free(clist.caps);

    var t1 = Thread.init(1, &clist, null, 0x1000, 0x500);
    t1.priority = 1; // High priority

    var t2 = Thread.init(2, &clist, null, 0x2000, 0x600);
    t2.priority = 2; // Normal priority

    try sched.addThread(&t1);
    try sched.addThread(&t2);

    // Should schedule t1 (higher priority)
    const run1 = sched.schedule().?;
    try std.testing.expectEqual(run1.id, 1);

    // Block t1
    sched.blockThread(1, .ipc_recv, 100);
    try std.testing.expectEqual(t1.state, ThreadState.blocked);

    // Now should schedule t2
    const run2 = sched.schedule().?;
    try std.testing.expectEqual(run2.id, 2);

    // Unblock t1 waiting on object 100
    sched.unblockThreadsWaitingOn(.ipc_recv, 100);
    try std.testing.expectEqual(t1.state, ThreadState.ready);

    // Should schedule t1 again
    const run3 = sched.schedule().?;
    try std.testing.expectEqual(run3.id, 1);
}
