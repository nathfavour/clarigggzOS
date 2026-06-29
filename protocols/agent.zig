const std = @import("std");

/// AgentPort protocol for autonomous agent task delegation.
pub const AgentPort = struct {
    pub const ProtocolID: u32 = 0xCAF4;

    pub const TaskKind = enum(u8) {
        infer,
        plan,
        observe,
        sync,
    };

    pub const Task = struct {
        kind: TaskKind,
        agent_id: u32,
        priority: u8,
        token_budget: u16,
        payload_len: u16,
    };

    pub const Result = struct {
        agent_id: u32,
        status: enum(u8) { ok, deferred, failed },
        tokens_used: u16,
    };
};
