const std = @import("std");
const protocols = @import("protocols");
const Message = protocols.ipc.Message;

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
        const syscall = std.meta.intToEnum(Syscall, call_num) catch return .{ .code = 1, .data = 0 };

        switch (syscall) {
            .ipc_send => {
                // a1: cap_index, a2: ptr to Message
                // This would call ipc_router.deliver(...)
                return .{ .code = 0, .data = 0 };
            },
            .ipc_recv => {
                // a1: port_id
                return .{ .code = 0, .data = 0 };
            },
            .yield => {
                // Trigger scheduler
                return .{ .code = 0, .data = 0 };
            },
            .log => {
                // Debug log from user-space
                return .{ .code = 0, .data = 0 };
            },
            else => return .{ .code = 1, .data = 0 },
        }
    }
};
