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
    submit_intent = 5,
    keychain_seal = 6,
    keychain_open = 7,
    log = 255,
};

pub const Result = struct {
    code: u64,
    data: u64,
};

fn rescheduleFrom(current: *main.scheduler.Thread) void {
    current.state = .ready;
    if (main.core_scheduler.schedule()) |next| {
        main.current_thread = next;
        if (next.id != current.id) {
            main.scheduler.switch_context(&current.ctx, &next.ctx);
        } else {
            next.state = .running;
        }
    }
}

pub const Dispatcher = struct {
    pub fn handle(call_num: u64, a1: u64, a2: u64, a3: u64) Result {
        const syscall_id = std.enums.fromInt(Syscall, call_num) orelse return .{ .code = 1, .data = 0 };
        const current_thread = main.current_thread orelse main.core_scheduler.getCurrentThread() orelse return .{ .code = 3, .data = 0 };

        switch (syscall_id) {
            .ipc_send => {
                const cap_index: usize = @intCast(a1);
                const msg_ptr = @as(*const Message, @ptrFromInt(a2));
                main.ipc_router.deliver(current_thread.clist, cap_index, msg_ptr.*, current_thread.id, &main.core_scheduler) catch |err| {
                    if (err == error.Blocked) {
                        rescheduleFrom(current_thread);
                        return .{ .code = 2, .data = 0 };
                    }
                    return .{ .code = 1, .data = 0 };
                };
                return .{ .code = 0, .data = 0 };
            },
            .ipc_recv => {
                const cap_index: usize = @intCast(a1);
                const msg_out = @as(*Message, @ptrFromInt(a2));
                const msg = main.ipc_router.receive(current_thread.clist, cap_index, current_thread.id, &main.core_scheduler) catch |err| {
                    if (err == error.Blocked) {
                        rescheduleFrom(current_thread);
                        return .{ .code = 2, .data = 0 };
                    }
                    return .{ .code = 1, .data = 0 };
                };
                msg_out.* = msg;
                return .{ .code = 0, .data = 0 };
            },
            .yield => {
                rescheduleFrom(current_thread);
                return .{ .code = 0, .data = 0 };
            },
            .get_cap => {
                const cap_index: usize = @intCast(a1);
                const cap = current_thread.clist.get(cap_index) orelse return .{ .code = 1, .data = 0 };
                return .{ .code = 0, .data = @intFromEnum(cap.cap_type) };
            },
            .submit_intent => {
                const tap_id: u16 = @intCast(a1);
                const timestamp: u64 = a2;
                const biometric = a3 != 0;
                main.handlePhysicalIntent(tap_id, timestamp, biometric);
                return .{ .code = 0, .data = @intFromEnum(main.security_manager.state) };
            },
            .keychain_seal => {
                // Multi-buffer seal requests use KeychainPort IPC until UTM marshaling lands.
                return .{ .code = 4, .data = 0 };
            },
            .keychain_open => {
                const cap_index: usize = @intCast(a1);
                const item_id: u32 = @intCast(a2);
                const out_ptr = @as([*]u8, @ptrFromInt(a3));
                var buf: [main.tee_mod.keychain.max_blob_len]u8 = undefined;
                const n = main.clarigggz_keychain.open(current_thread.clist, cap_index, item_id, &buf) catch {
                    return .{ .code = 1, .data = 0 };
                };
                @memcpy(out_ptr[0..n], buf[0..n]);
                return .{ .code = 0, .data = n };
            },
            .log => {
                const str_ptr = @as([*]const u8, @ptrFromInt(a1));
                const len: usize = @intCast(a2);
                main.printString("[adapter] ");
                main.printString(str_ptr[0..len]);
                main.printString("\n");
                return .{ .code = 0, .data = 0 };
            },
        }
    }
};
