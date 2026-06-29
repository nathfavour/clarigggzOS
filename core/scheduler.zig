const std = @import("std");
const capability = @import("capability.zig");

/// CPU register context for cooperative context switch (matches arch/riscv64/k1/switch.S).
pub const CpuContext = extern struct {
    ra: u64 = 0,
    sp: u64 = 0,
    s0: u64 = 0,
    s1: u64 = 0,
    s2: u64 = 0,
    s3: u64 = 0,
    s4: u64 = 0,
    s5: u64 = 0,
    s6: u64 = 0,
    s7: u64 = 0,
    s8: u64 = 0,
    s9: u64 = 0,
    s10: u64 = 0,
    s11: u64 = 0,
};

pub extern fn riscv_switch_context(old_ctx: *CpuContext, new_ctx: *CpuContext) callconv(.c) void;

pub fn switch_context(old_ctx: *CpuContext, new_ctx: *CpuContext) callconv(.c) void {
    const builtin = @import("builtin");
    if (comptime builtin.cpu.arch == .riscv64 and builtin.os.tag == .freestanding) {
        riscv_switch_context(old_ctx, new_ctx);
    }
}

pub const ThreadState = enum {
    ready,
    running,
    blocked,
};

pub const WaitReason = enum {
    none,
    ipc_send,
    ipc_recv,
    sleep,
};

pub const Thread = struct {
    id: u32,
    clist: *capability.CList,
    parent_clist: ?*capability.CList,

    ctx: CpuContext = .{},
    uses_vectors: bool = false,

    state: ThreadState = .ready,
    priority: u8 = 10,

    wait_reason: WaitReason = .none,
    wait_object_id: u64 = 0,

    pub fn init(id: u32, clist: *capability.CList, parent_clist: ?*capability.CList, stack_top: u64, entry: u64) Thread {
        return .{
            .id = id,
            .clist = clist,
            .parent_clist = parent_clist,
            .ctx = .{
                .ra = entry,
                .sp = stack_top,
            },
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
    threads: [64]?*Thread,
    thread_count: usize = 0,
    current_idx: usize = 0,

    pub fn init() Scheduler {
        return .{
            .threads = [_]?*Thread{null} ** 64,
            .thread_count = 0,
        };
    }

    pub fn addThread(self: *Scheduler, thread: *Thread) !void {
        if (self.thread_count >= 64) return error.NoFreeThreadSlots;
        self.threads[self.thread_count] = thread;
        self.thread_count += 1;
    }

    pub fn deinit(self: *Scheduler) void {
        _ = self;
    }

    pub fn schedule(self: *Scheduler) ?*Thread {
        if (self.thread_count == 0) return null;

        var selected_thread: ?*Thread = null;
        var best_prio: u8 = 255;
        var best_idx: ?usize = null;

        const count = self.thread_count;
        const start_idx = self.current_idx;
        var i: usize = 0;
        while (i < count) : (i += 1) {
            const idx = (start_idx + 1 + i) % count;
            if (self.threads[idx]) |t| {
                if (t.state == .ready or t.state == .running) {
                    if (t.priority < best_prio) {
                        best_prio = t.priority;
                        selected_thread = t;
                        best_idx = idx;
                    }
                }
            }
        }

        if (selected_thread) |t| {
            if (best_idx) |idx| self.current_idx = idx;
            for (self.threads[0..self.thread_count]) |maybe_other| {
                if (maybe_other) |other| {
                    if (other.id != t.id and other.state == .running) {
                        other.state = .ready;
                    }
                }
            }
            t.state = .running;
            return t;
        }
        return null;
    }

    pub fn getCurrentThread(self: *const Scheduler) ?*Thread {
        for (self.threads[0..self.thread_count]) |maybe_t| {
            if (maybe_t) |t| {
                if (t.state == .running) return t;
            }
        }
        return null;
    }

    pub fn blockThread(self: *Scheduler, thread_id: u32, reason: WaitReason, object_id: u64) void {
        for (self.threads[0..self.thread_count]) |maybe_t| {
            if (maybe_t) |t| {
                if (t.id == thread_id) {
                    t.block(reason, object_id);
                    break;
                }
            }
        }
    }

    pub fn unblockThread(self: *Scheduler, thread_id: u32) void {
        for (self.threads[0..self.thread_count]) |maybe_t| {
            if (maybe_t) |t| {
                if (t.id == thread_id) {
                    t.unblock();
                    break;
                }
            }
        }
    }

    pub fn unblockThreadsWaitingOn(self: *Scheduler, reason: WaitReason, object_id: u64) void {
        for (self.threads[0..self.thread_count]) |maybe_t| {
            if (maybe_t) |t| {
                if (t.state == .blocked and t.wait_reason == reason and t.wait_object_id == object_id) {
                    t.unblock();
                }
            }
        }
    }
};

test "Scheduler - Priority Scheduling and Blocking" {
    const allocator = std.testing.allocator;

    var sched = Scheduler.init();
    defer sched.deinit();

    var clist: capability.CList = undefined;
    capability.CList.initTest(&clist, allocator, 4, 1);
    defer allocator.free(clist.caps);

    var t1 = Thread.init(1, &clist, null, 0x1000, 0x500);
    t1.priority = 20;

    var t2 = Thread.init(2, &clist, null, 0x2000, 0x600);
    t2.priority = 10;

    try sched.addThread(&t1);
    try sched.addThread(&t2);

    const next1 = sched.schedule().?;
    try std.testing.expectEqual(next1.id, 2);

    sched.blockThread(2, .sleep, 100);
    try std.testing.expectEqual(t2.state, ThreadState.blocked);

    const next2 = sched.schedule().?;
    try std.testing.expectEqual(next2.id, 1);

    sched.unblockThread(2);
    const next3 = sched.schedule().?;
    try std.testing.expectEqual(next3.id, 2);
}
