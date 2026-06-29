const std = @import("std");
const protocols = @import("protocols");

pub const AgentState = enum {
    idle,
    ready,
    running,
    blocked,
};

pub const Agent = struct {
    id: u32,
    name: [16]u8,
    name_len: u8,
    priority: u8,
    state: AgentState = .idle,
    neural_port: u32 = 0,
    tokens_consumed: u64 = 0,
};

pub const AgentRuntime = struct {
    agents: [16]Agent,
    agent_count: usize = 0,
    tick_count: u64 = 0,
    next_id: u32 = 1,

    pub fn init() AgentRuntime {
        return .{
            .agents = undefined,
        };
    }

    pub fn register(self: *AgentRuntime, name: []const u8, priority: u8, neural_port: u32) !u32 {
        if (self.agent_count >= self.agents.len) return error.TooManyAgents;
        const id = self.next_id;
        self.next_id += 1;

        var agent = Agent{
            .id = id,
            .name = undefined,
            .name_len = @intCast(@min(name.len, 16)),
            .priority = priority,
            .state = .ready,
            .neural_port = neural_port,
        };
        @memset(&agent.name, 0);
        @memcpy(agent.name[0..agent.name_len], name[0..agent.name_len]);

        self.agents[self.agent_count] = agent;
        self.agent_count += 1;
        return id;
    }

    pub fn scheduleNext(self: *AgentRuntime) ?*Agent {
        var best: ?*Agent = null;
        var best_prio: u8 = 255;
        for (&self.agents, 0..) |*agent, i| {
            if (i >= self.agent_count) break;
            if (agent.state == .ready and agent.priority < best_prio) {
                best_prio = agent.priority;
                best = agent;
            }
        }
        if (best) |a| {
            a.state = .running;
            return a;
        }
        return null;
    }

    pub fn completeTask(self: *AgentRuntime, agent_id: u32, tokens: u16) void {
        for (&self.agents, 0..) |*agent, i| {
            if (i >= self.agent_count) break;
            if (agent.id == agent_id) {
                agent.tokens_consumed += tokens;
                agent.state = .ready;
                return;
            }
        }
    }

    pub fn tick(self: *AgentRuntime) void {
        self.tick_count += 1;
        if (self.scheduleNext()) |agent| {
            agent.tokens_consumed += 1;
            agent.state = .ready;
            _ = protocols.agent.AgentPort.Task{
                .kind = .infer,
                .agent_id = agent.id,
                .priority = agent.priority,
                .token_budget = 128,
                .payload_len = 0,
            };
        }
    }
};

test "Agent runtime registration" {
    var rt = AgentRuntime.init();
    const id = try rt.register("planner", 5, 2);
    try std.testing.expect(id == 1);
    try std.testing.expect(rt.agent_count == 1);
}
