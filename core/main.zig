const std = @import("std");
const protocols = @import("protocols");
const Message = protocols.ipc.Message;
const config = @import("config");

const builtin = @import("builtin");

// Disable threaded IO dependencies for freestanding RISC-V targets
pub const std_options_debug_threaded_io: ?*anyopaque = null;

/// Hardware mapping pattern via Comptime
pub fn HardwareRegisterMap(comptime base_addr: usize) type {
    return packed struct {
        control_bits: u4,
        interrupt_mask: u1,
        frequency_divider: u3,
        reserved: u24,

        const Self = @This();
        pub inline fn get() *volatile Self {
            return @ptrFromInt(base_addr);
        }
    };
}

/// Generic 16550A UART Driver
pub fn Uart16550(comptime base_addr: usize) type {
    return struct {
        pub const THR: *volatile u8 = @ptrFromInt(base_addr + 0);
        pub const IER: *volatile u8 = @ptrFromInt(base_addr + 1);
        pub const FCR: *volatile u8 = @ptrFromInt(base_addr + 2);
        pub const LCR: *volatile u8 = @ptrFromInt(base_addr + 3);
        pub const LSR: *volatile u8 = @ptrFromInt(base_addr + 5);

        pub fn init() void {
            IER.* = 0x00; // Disable all interrupts
            LCR.* = 0x80; // Enable DLAB (divisor latch access bit)
            
            // Set divisor latch for baud rate 115200 (divisor = 3)
            const dll: *volatile u8 = @ptrFromInt(base_addr + 0);
            const dlm: *volatile u8 = @ptrFromInt(base_addr + 1);
            dll.* = 0x03;
            dlm.* = 0x00;

            LCR.* = 0x03; // 8 bits, no parity, one stop bit (DLAB disabled)
            FCR.* = 0xC7; // Enable FIFO, clear RX/TX FIFO, 14-byte threshold
        }

        pub fn putc(c: u8) void {
            // Wait for Transmitter Holding Register Empty (bit 5 of LSR)
            while ((LSR.* & 0x20) == 0) {}
            THR.* = c;
        }

        pub fn puts(str: []const u8) void {
            for (str) |c| {
                putc(c);
            }
        }
    };
}

pub const TargetHardware = enum {
    qemu_virt,
    spacemit_k1,
};

pub const current_hardware: TargetHardware = if (std.mem.eql(u8, config.hardware, "spacemit_k1"))
    .spacemit_k1
else
    .qemu_virt;

pub const uart_base = switch (current_hardware) {
    .qemu_virt => 0x10000000,
    .spacemit_k1 => 0xD8000000, // SpacemiT K1 UART0 base
};

pub const system_uart = Uart16550(uart_base);

/// Microkernel state
const CoreBroker = struct {
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

pub var kernel_heap: memory.KernelHeap = undefined;
pub var ipc_router: ipc_transport.Router = undefined;
pub var core_scheduler: scheduler.Scheduler = undefined;
pub var security_manager: security.SecurityManager = undefined;
pub var tap_verifier: physical_intent.PhysicalSequenceVerifier = undefined;

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
            _ = syscall.Dispatcher.handle(0, 0, 0, 0);
            _ = sepc;
        } else {
            while (true) {} // Kernel Panic
        }
    }
    _ = stval;
}

pub fn printString(str: []const u8) void {
    if (comptime builtin.os.tag == .freestanding) {
        system_uart.puts(str);
    } else {
        std.debug.print("{s}", .{str});
    }
}

pub fn printCentered(str: []const u8, width: usize) void {
    if (str.len >= width) {
        printString(str);
        printString("\n");
        return;
    }
    const pad = (width - str.len) / 2;
    var i: usize = 0;
    while (i < pad) : (i += 1) {
        printString(" ");
    }
    printString(str);
    printString("\n");
}

/// The Zig Entry Point from arch/riscv64/k1/boot.S
export fn kmain() noreturn {
    if (comptime builtin.os.tag == .freestanding) {
        system_uart.init();
    }
    // Print centered boot banner
    printString("\n");
    printCentered("================================================================================", 80);
    printCentered("______ _            _                             ____   _____", 80);
    printCentered("/ ____/| |          (_)                           / __ \\ / ____|", 80);
    printCentered("| |     | | __ _ _ __ _  __ _  __ _  __ _ ____    | |  | | (___  ", 80);
    printCentered("| |     | |/ _` | '__| |/ _` |/ _` |/ _` |_  /    | |  | |\\___ \\ ", 80);
    printCentered("| |____ | | (_| | |  | | (_| | (_| | (_| |/ /     | |__| |____) |", 80);
    printCentered("\\_____/|_|\\__,_|_|  |_|\\__, |\\__, |\\__, /___|     \\____/|_____/ ", 80);
    printCentered("                        __/ | __/ | __/ |                       ", 80);
    printCentered("                       |___/ |___/ |___/                        ", 80);
    printCentered("================================================================================", 80);
    printCentered("The Agent-Native Sovereign OS | RISC-V 64 Hexagonal Microkernel", 80);
    printCentered("Booting Kernel version 0.1.0 ...", 80);
    printString("\n");

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
        // Wait For Interrupt (WFI / HLT)
        if (builtin.cpu.arch == .riscv64) {
            asm volatile ("wfi");
        } else if (builtin.cpu.arch == .x86_64) {
            asm volatile ("hlt");
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
