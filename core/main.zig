const std = @import("std");
const protocols = @import("protocols");
const Message = protocols.ipc.Message;

/// Microkernel state
const CoreBroker = struct {
    // Basic scheduler and memory state for the K1 core.
    capabilities: std.ArrayList(u64), // Placeholder for actual C-list management.
    
    pub fn init(allocator: std.mem.Allocator) CoreBroker {
        return .{
            .capabilities = std.ArrayList(u64).init(allocator),
        };
    }
};

const memory = @import("memory.zig");
const capability = @import("capability.zig");
const ipc_transport = @import("ipc_transport.zig");

var kernel_heap: memory.KernelHeap = undefined;
var ipc_router: ipc_transport.Router = undefined;

/// The Zig Entry Point from arch/riscv64/k1/boot.S
export fn kmain() noreturn {
    // 1. Initialize Kernel Heap (1MB for early boot)
    kernel_heap = memory.KernelHeap.init(0x80100000, 1024);
    const allocator = kernel_heap.allocator();

    // 2. Initialize the IPC Router
    ipc_router = ipc_transport.Router.init(allocator);

    // 3. Initialize the Root Capability List
    var root_clist = capability.CList.init(allocator, 64, 0) catch {
        while (true) {} // Kernel Panic: Failed to init root CList
    };

    // 4. Create an initial system port
    _ = ipc_router.createPort(0, &root_clist) catch {
        while (true) {} // Kernel Panic: Failed to create root port
    };

    // Core Loop: Dispatching to IPC routing and the scheduler.
    while (true) {
        // Article I: The Power Budget
        // Wait For Interrupt (WFI)
        asm volatile ("wfi");
    }
}

pub fn main() void {
    // This main is for simulation/unit testing if needed,
    // but the actual kernel uses 'kmain' as the primary entry.
}
