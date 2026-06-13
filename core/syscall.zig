const std = @import("std");
const protocols = @import("protocols");
const Message = protocols.ipc.Message;
const main = @import("main.zig");

/// Clarigggz OS System Call Numbers
pub const Syscall = enum(u64) {
    ipc_send = 1,
    ipc_recv = 2,
    yield = 3,
    get_cap = 4,
    log = 255, // Debug log syscall
};

/// The Syscall Result structure returned to user-space.
pub const Result = struct {
    code: u64,
    data: u64,
};

/// Dispatcher for system calls coming from user-space (ecall).
pub const Dispatcher = struct {
    pub fn handle(call_num: u64, a1: u64, a2: u64, a3: u64) Result {
        _ = a3;
        const syscall = std.enums.fromInt(Syscall, call_num) orelse return .{ .code = 1, .data = 0 };

        // Fetch current running thread
        const current_thread = main.core_scheduler.getCurrentThread() orelse return .{ .code = 3, .data = 0 }; // Code 3: No Thread running

        switch (syscall) {
            .ipc_send => {
                // a1: cap_index, a2: ptr to Message
                const cap_index: usize = a1;
                const msg_ptr = @as(*const Message, @ptrFromInt(a2));

                main.ipc_router.deliver(current_thread.clist, cap_index, msg_ptr.*, current_thread.id, &main.core_scheduler) catch |err| {
                    if (err == error.Blocked) {
                        return .{ .code = 2, .data = 0 }; // Blocked / Context switch needed
                    }
                    return .{ .code = 1, .data = 0 };
                };
                return .{ .code = 0, .data = 0 };
            },
            .ipc_recv => {
                // a1: cap_index, a2: ptr to Message (where to copy)
                const cap_index: usize = a1;
                const msg_out = @as(*Message, @ptrFromInt(a2));

                const msg = main.ipc_router.receive(current_thread.clist, cap_index, current_thread.id, &main.core_scheduler) catch |err| {
                    if (err == error.Blocked) {
                        return .{ .code = 2, .data = 0 };
                    }
                    return .{ .code = 1, .data = 0 };
                };
                msg_out.* = msg;
                return .{ .code = 0, .data = 0 };
            },
            .yield => {
                current_thread.state = .ready;
                return .{ .code = 0, .data = 0 };
            },
            .get_cap => {
                const cap_index: usize = a1;
                const cap = current_thread.clist.get(cap_index) orelse return .{ .code = 1, .data = 0 };
                return .{ .code = 0, .data = @intFromEnum(cap.cap_type) };
            },
            .log => {
                const str_ptr = @as([*]const u8, @ptrFromInt(a1));
                const len: usize = a2;
                // Safely log user string
                if (comptime @import("builtin").os.tag != .freestanding) {
                    std.debug.print("[Syscall Log] {s}\n", .{str_ptr[0..len]});
                }
                return .{ .code = 0, .data = 0 };
            },
        }
    }
};
