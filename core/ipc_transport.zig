const std = @import("std");
const capability = @import("capability.zig");
const scheduler = @import("scheduler.zig");
const protocols = @import("protocols");
const Message = protocols.ipc.Message;

/// A Port is a kernel-managed endpoint for IPC.
pub const Port = struct {
    id: u32,
    owner_id: u32,
    receiver_clist: *capability.CList,
    
    // A simple circular buffer for message queueing.
    // Article I: Zero-Cost Abstraction - fixed size for predictability.
    queue: [16]Message,
    head: u8 = 0,
    tail: u8 = 0,
    count: u8 = 0,

    pub fn isFull(self: *const Port) bool {
        return self.count == self.queue.len;
    }

    pub fn isEmpty(self: *const Port) bool {
        return self.count == 0;
    }

    pub fn push(self: *Port, msg: Message) !void {
        if (self.isFull()) return error.PortFull;
        self.queue[self.tail] = msg;
        self.tail = (self.tail + 1) % @as(u8, @intCast(self.queue.len));
        self.count += 1;
    }

    pub fn pop(self: *Port) ?Message {
        if (self.isEmpty()) return null;
        const msg = self.queue[self.head];
        self.head = (self.head + 1) % @as(u8, @intCast(self.queue.len));
        self.count -= 1;
        return msg;
    }
};

/// The IPC Router manages all Ports and ensures capability checks.
pub const Router = struct {
    ports: std.AutoHashMap(u32, *Port),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Router {
        return .{
            .ports = std.AutoHashMap(u32, *Port).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn createPort(self: *Router, owner_id: u32, receiver_clist: *capability.CList) !u32 {
        const port_id = @as(u32, @intCast(self.ports.count())); // Simple ID generation
        const port = try self.allocator.create(Port);
        port.* = .{
            .id = port_id,
            .owner_id = owner_id,
            .receiver_clist = receiver_clist,
            .queue = undefined,
            .head = 0,
            .tail = 0,
            .count = 0,
        };
        try self.ports.put(port_id, port);
        return port_id;
    }

    /// Deliver a message after verifying the sender has the required capability.
    /// If the port is full, block the sender thread.
    pub fn deliver(self: *Router, sender_clist: *const capability.CList, cap_index: usize, msg: Message, sender_id: u32, sched: *scheduler.Scheduler) !void {
        const cap = sender_clist.get(cap_index) orelse return error.InvalidCapability;
        
        if (cap.cap_type != .ipc_endpoint) return error.WrongCapType;
        if ((cap.rights & capability.Capability.Rights.write) == 0) return error.NoWriteAccess;

        const port = self.ports.get(@as(u32, @intCast(cap.object_id))) orelse return error.PortNotFound;
        
        if (port.isFull()) {
            // Block sender on this port
            sched.blockThread(sender_id, .ipc_send, port.id);
            return error.Blocked;
        }

        try port.push(msg);

        // If any receiver is blocked waiting for this port, unblock them
        sched.unblockThreadsWaitingOn(.ipc_recv, port.id);
    }

    /// Receive a message from a port after verifying capability.
    /// If the port is empty, block the receiver thread.
    pub fn receive(self: *Router, receiver_clist: *const capability.CList, cap_index: usize, receiver_id: u32, sched: *scheduler.Scheduler) !Message {
        const cap = receiver_clist.get(cap_index) orelse return error.InvalidCapability;
        
        if (cap.cap_type != .ipc_endpoint) return error.WrongCapType;
        if ((cap.rights & capability.Capability.Rights.read) == 0) return error.NoReadAccess;

        const port = self.ports.get(@as(u32, @intCast(cap.object_id))) orelse return error.PortNotFound;

        if (port.isEmpty()) {
            // Block receiver on this port
            sched.blockThread(receiver_id, .ipc_recv, port.id);
            return error.Blocked;
        }

        const msg = port.pop().?;

        // If any sender is blocked waiting to write to this port, unblock them
        sched.unblockThreadsWaitingOn(.ipc_send, port.id);

        return msg;
    }
};

test "IPC Router - Port Blocking and Wakeup" {
    const allocator = std.testing.allocator;

    var router = Router.init(allocator);
    defer {
        var it = router.ports.iterator();
        while (it.next()) |entry| {
            allocator.destroy(entry.value_ptr.*);
        }
        router.ports.deinit();
    }

    var clist_sender = try capability.CList.init(allocator, 4, 1);
    defer allocator.free(clist_sender.caps);

    var clist_receiver = try capability.CList.init(allocator, 4, 2);
    defer allocator.free(clist_receiver.caps);

    var sched = scheduler.Scheduler.init(allocator);
    defer sched.deinit();

    var t_sender = scheduler.Thread.init(1, &clist_sender, null, 0x1000, 0x500);
    var t_receiver = scheduler.Thread.init(2, &clist_receiver, null, 0x2000, 0x600);

    try sched.addThread(&t_sender);
    try sched.addThread(&t_receiver);

    const port_id = try router.createPort(2, &clist_receiver);

    // Set sender endpoint cap
    clist_sender.caps[0] = .{
        .cap_type = .ipc_endpoint,
        .rights = capability.Capability.Rights.write,
        .object_id = @as(u24, @intCast(port_id)),
        .base = 0,
        .limit = 0,
    };

    // Set receiver endpoint cap
    clist_receiver.caps[0] = .{
        .cap_type = .ipc_endpoint,
        .rights = capability.Capability.Rights.read,
        .object_id = @as(u24, @intCast(port_id)),
        .base = 0,
        .limit = 0,
    };

    const msg = Message{
        .sender_id = 1,
        .protocol_id = 42,
        .payload_len = 0,
        .capability_bits = 0,
        .payload = [_]u8{0} ** 128,
    };

    // Receive on empty port should return error.Blocked and block receiver thread
    const recv_res = router.receive(&clist_receiver, 0, 2, &sched);
    try std.testing.expectError(error.Blocked, recv_res);
    try std.testing.expectEqual(t_receiver.state, scheduler.ThreadState.blocked);

    // Deliver message: should succeed and unblock the receiver
    try router.deliver(&clist_sender, 0, msg, 1, &sched);
    try std.testing.expectEqual(t_receiver.state, scheduler.ThreadState.ready);

    // Receiver should now successfully receive the message without blocking
    const received = try router.receive(&clist_receiver, 0, 2, &sched);
    try std.testing.expectEqual(received.protocol_id, 42);
}
