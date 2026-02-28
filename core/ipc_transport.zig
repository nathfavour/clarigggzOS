const std = @import("std");
const capability = @import("capability.zig");
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
    pub fn deliver(self: *Router, sender_clist: *const capability.CList, cap_index: usize, msg: Message) !void {
        const cap = sender_clist.get(cap_index) orelse return error.InvalidCapability;
        
        if (cap.cap_type != .ipc_endpoint) return error.WrongCapType;
        if ((cap.rights & capability.Capability.Rights.write) == 0) return error.NoWriteAccess;

        const port = self.ports.get(@as(u32, @intCast(cap.object_id))) orelse return error.PortNotFound;
        try port.push(msg);
    }
};
