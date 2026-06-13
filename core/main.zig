const std = @import("std");
const protocols = @import("protocols");
const Message = protocols.ipc.Message;

const builtin = @import("builtin");

/// Microkernel state
const CoreBroker = struct {
    // Basic scheduler and memory state for the K1 core.
    capabilities: std.ArrayList(u64), // Placeholder for actual C-list management.
    
    pub fn init(allocator: std.mem.Allocator) CoreBroker {
        _ = allocator;
        return .{
            .capabilities = .empty,
        };
    }
};

pub const memory = @import("memory.zig");
pub const capability = @import("capability.zig");
pub const ipc_transport = @import("ipc_transport.zig");
pub const scheduler = @import("scheduler.zig");
pub const security = @import("security.zig");
pub const physical_intent = @import("physical_intent.zig");

var kernel_heap: memory.KernelHeap = undefined;
var ipc_router: ipc_transport.Router = undefined;
var core_scheduler: scheduler.Scheduler = undefined;
var security_manager: security.SecurityManager = undefined;
var tap_verifier: physical_intent.PhysicalSequenceVerifier = undefined;

const syscall = @import("syscall.zig");

/// The primary trap handler called from arch/riscv64/k1/trap.S
export fn k_trap_handler(scause: u64, sepc: u64, stval: u64) void {
    const is_interrupt = (scause >> 63) == 1;
    const code = scause & 0xFFF;

    if (is_interrupt) {
        // Handle Hardware Interrupts (PLIC/CLINT)
    } else {
        // Handle Synchronous Traps (Syscalls, Faults)
        if (code == 8 or code == 9) { // Environment Call (User or Supervisor)
            // Syscall logic here
            // We would read registers a7 (syscall num), a0, a1, a2 (args)
            // from the thread's saved context.
            
            // For now, mock a call to the dispatcher
            _ = syscall.Dispatcher.handle(0, 0, 0, 0);
            
            // Increment sepc to point to the instruction after ecall
            _ = sepc; // In a real system, we'd update thread.context.mepc
        } else {
            // Memory Fault or Illegal Instruction
            while (true) {} // Kernel Panic
        }
    }
    _ = stval;
}

/// The Zig Entry Point from arch/riscv64/k1/boot.S
export fn kmain() noreturn {
    // ... rest of init ...
    // 1. Initialize Kernel Heap (1MB for early boot)
    kernel_heap = memory.KernelHeap.init(0x80100000, 1024);
    const allocator = kernel_heap.allocator();

    // 2. Initialize the IPC Router
    ipc_router = ipc_transport.Router.init(allocator);

    // 3. Initialize the Scheduler
    core_scheduler = scheduler.Scheduler.init(allocator);

    // 4. Initialize Security Subsystems
    security_manager = security.SecurityManager{};
    tap_verifier = physical_intent.PhysicalSequenceVerifier{};

    // 5. Initialize the Root Capability List
    var root_clist = capability.CList.init(allocator, 64, 0) catch {
        while (true) {} // Kernel Panic: Failed to init root CList
    };

    // 6. Create the first system thread (Primary Manager)
    const root_thread = allocator.create(scheduler.Thread) catch {
        while (true) {} // Kernel Panic
    };
    root_thread.* = scheduler.Thread.init(0, &root_clist, null, 0x801FFFFF, 0x80000000);
    core_scheduler.addThread(root_thread) catch {};

    // 7. Create an initial system port
    _ = ipc_router.createPort(0, &root_clist) catch {
        while (true) {} // Kernel Panic: Failed to create root port
    };

    // Core Loop: Dispatching to IPC routing and the scheduler.
    while (true) {
        // Find next thread to run
        if (core_scheduler.schedule()) |next_thread| {
            _ = next_thread;
            // TODO: Assembly-level context switch call
        }

        // Article I: The Power Budget
        // Wait For Interrupt (WFI)
        if (builtin.cpu.arch == .riscv64) {
            asm volatile ("wfi");
        }
    }
}

pub fn main() void {
    // Standard Zig main for simulation or unit testing
}

test "IPC Router - Port Creation and Message Delivery" {
    const allocator = std.testing.allocator;
    
    // 1. Setup subsystems
    var router = ipc_transport.Router.init(allocator);
    defer {
        var it = router.ports.iterator();
        while (it.next()) |entry| {
            allocator.destroy(entry.value_ptr.*);
        }
        router.ports.deinit();
    }

    var clist = try capability.CList.init(allocator, 4, 1);
    defer allocator.free(clist.caps);

    // 2. Create a port
    const port_id = try router.createPort(1, &clist);
    
    // 3. Grant capability to send to this port
    clist.caps[0] = .{
        .cap_type = .ipc_endpoint,
        .rights = capability.Capability.Rights.write,
        .object_id = @as(u24, @intCast(port_id)),
        .base = 0,
        .limit = 0,
    };

    var sched = scheduler.Scheduler.init(allocator);
    defer sched.deinit();

    // 4. Send a message
    const msg = protocols.ipc.Message{
        .sender_id = 1,
        .protocol_id = 42,
        .payload_len = 0,
        .capability_bits = 0,
        .payload = [_]u8{0} ** 128,
    };

    try router.deliver(&clist, 0, msg, 1, &sched);

    // 5. Verify delivery
    const port = router.ports.get(port_id).?;
    const delivered = port.pop().?;
    try std.testing.expectEqual(delivered.protocol_id, 42);
}
