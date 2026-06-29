const std = @import("std");
const protocols = @import("protocols");
const Message = protocols.ipc.Message;
const config = @import("config");

const builtin = @import("builtin");
extern fn kernel_alloc(len: u64, align_bytes: u64) ?[*]u8;

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
pub const paging = @import("paging.zig");
pub const rvv = @import("rvv.zig");
pub const elf_loader = @import("elf_loader.zig");
pub const plic_dev = @import("plic.zig");
pub const irq_router_mod = @import("irq_router.zig");
pub const framebuffer_mod = @import("framebuffer.zig");
pub const secure_enclave_mod = @import("secure_enclave.zig");
pub const tee_mod = @import("tee/root.zig");
pub const agent_runtime_mod = @import("agent_runtime.zig");

pub var kernel_heap: memory.KernelHeap = undefined;
pub const kernel_heap_vtable = std.mem.Allocator.VTable{
    .alloc = memory.KernelHeap.alloc_adapter,
    .resize = memory.KernelHeap.resize_adapter,
    .remap = memory.KernelHeap.remap_adapter,
    .free = memory.KernelHeap.free_adapter,
};
pub var ipc_router: ipc_transport.Router = undefined;
pub var core_scheduler: scheduler.Scheduler = undefined;
pub var security_manager: security.SecurityManager = undefined;
pub var tap_verifier: physical_intent.PhysicalSequenceVerifier = undefined;
pub var kernel_aspace_storage: paging.AddressSpace = undefined;
pub var current_thread: ?*scheduler.Thread = null;
pub var scheduler_ctx: scheduler.CpuContext = .{};
pub var waveguide_fb: framebuffer_mod.Framebuffer = undefined;
pub var irq_router: irq_router_mod.IrqRouter = undefined;
pub var clarigggz_keychain: tee_mod.Keychain = undefined;
pub var agent_runtime: agent_runtime_mod.AgentRuntime = undefined;
pub var clint_dev: plic_dev.Clint = undefined;

fn onAgentIrq() void {
    agent_runtime.tick();
}

pub const plic_base = switch (current_hardware) {
    .qemu_virt => plic_dev.Plic.qemu_virt_base,
    .spacemit_k1 => plic_dev.Plic.spacemit_k1_base,
};

pub const clint_base = plic_dev.Clint.qemu_virt_base;
pub const enclave_base = tee_mod.layout.active.legacy_stub_enclave_base;

const syscall = @import("syscall.zig");

pub fn handlePhysicalIntent(tap_id: u16, timestamp: u64, biometric: bool) void {
    security_manager.handleTactileEvent(&tap_verifier, tap_id, timestamp, biometric, printString);
}

pub fn printHex(val: u64) void {
    const chars = "0123456789ABCDEF";
    var i: usize = 0;
    printString("0x");
    while (i < 16) : (i += 1) {
        const shift = @as(u6, @intCast((15 - i) * 4));
        const nibble = (val >> shift) & 0xF;
        const c = chars[nibble];
        if (comptime builtin.os.tag == .freestanding) {
            system_uart.putc(c);
        } else {
            std.debug.print("{c}", .{c});
        }
    }
}

/// The primary trap handler called from arch/riscv64/k1/trap.S
export fn k_trap_handler(scause: u64, sepc: u64, stval: u64, syscall_a0: u64, syscall_a1: u64, syscall_a2: u64, syscall_a3: u64) u64 {
    const is_interrupt = (scause >> 63) == 1;
    const code = scause & 0xFFF;

    if (is_interrupt) {
        if (comptime builtin.os.tag == .freestanding) {
            if (code == 9) {
                irq_router.dispatchPending(&ipc_router, &core_scheduler, onAgentIrq);
            } else if (code == 5) {
                irq_router.vsync_count += 1;
                clint_dev.armTimer(0, 16_666_666);
            }
        }
        return sepc;
    }

    if (code == 8 or code == 9) {
        _ = syscall.Dispatcher.handle(syscall_a0, syscall_a1, syscall_a2, syscall_a3);
        return sepc + 4;
    }

    printString("\n!!! KERNEL PANIC: CPU EXCEPTION !!!\n");
    printString("scause: ");
    printHex(scause);
    printString("\nsepc:   ");
    printHex(sepc);
    printString("\nstval:  ");
    printHex(stval);
    printString("\n");
    while (true) {}
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
    kernel_heap = memory.KernelHeap.init(0x80500000, 1024);
    const allocator = std.mem.Allocator{
        .ptr = &kernel_heap,
        .vtable = &kernel_heap_vtable,
    };

    // Initialize Paging (SV39)
    printString("[Boot] Initializing Sv39 Virtual Memory Page Tables...\n");
    const proto = struct {
        extern fn paging_init(out: *paging.AddressSpace, allocator_ptr: *anyopaque, allocator_vtable: *const std.mem.Allocator.VTable) void;
    };
    proto.paging_init(&kernel_aspace_storage, &kernel_heap, &kernel_heap_vtable);
    const kernel_aspace = &kernel_aspace_storage;

    // Identity map kernel memory: 0x80000000 up to 0x80800000 (8MB) to cover OpenSBI, Kernel, and Heap
    var page_addr: u64 = 0x80000000;
    while (page_addr < 0x80800000) : (page_addr += 4096) {
        if (comptime builtin.os.tag == .freestanding) {
            system_uart.putc('.');
        }
        kernel_aspace.map(page_addr, page_addr, paging.PTE.Flags.valid | paging.PTE.Flags.read | paging.PTE.Flags.write | paging.PTE.Flags.exec) catch {
            printString("[Panic] Failed to map kernel code region!\n");
            while (true) {}
        };
    }

    // Map physical MMIO UART base
    printString("[Boot] Mapping MMIO Hardware Address space...\n");
    kernel_aspace.map(uart_base, uart_base, paging.PTE.Flags.valid | paging.PTE.Flags.read | paging.PTE.Flags.write) catch {
        printString("[Panic] Failed to map UART MMIO region!\n");
        while (true) {}
    };

    // Map PLIC, CLINT, secure enclave MMIO, and waveguide framebuffer
    if (comptime builtin.os.tag == .freestanding) {
        kernel_aspace.map(plic_base, plic_base, paging.PTE.Flags.valid | paging.PTE.Flags.read | paging.PTE.Flags.write) catch {};
        kernel_aspace.map(clint_base, clint_base, paging.PTE.Flags.valid | paging.PTE.Flags.read | paging.PTE.Flags.write) catch {};
        kernel_aspace.map(enclave_base, enclave_base, paging.PTE.Flags.valid | paging.PTE.Flags.read | paging.PTE.Flags.write) catch {};
        waveguide_fb = framebuffer_mod.Framebuffer.init(framebuffer_mod.Framebuffer.default_base);
        waveguide_fb.mapRegion(kernel_aspace) catch {
            printString("[Panic] Failed to map waveguide framebuffer!\n");
        };
    }

    // Enable paging: load satp and flush TLB
    if (comptime builtin.cpu.arch == .riscv64 and builtin.os.tag == .freestanding) {
        printString("[Boot] Enabling virtual address translation (satp)...\n");
        const satp_val = kernel_aspace.satp();
        asm volatile (
            \\csrw satp, %[satp]
            \\sfence.vma
            :
            : [satp] "r" (satp_val)
        );
    }
    printString("[Boot] Virtual memory paging successfully activated!\n");

    // 2. Initialize the IPC Router
    printString("[Boot] Initializing IPC Router...\n");
    ipc_router = if (comptime builtin.os.tag == .freestanding)
        ipc_transport.Router.initKernel()
    else if (builtin.is_test)
        ipc_transport.Router.init(std.testing.allocator)
    else
        ipc_transport.Router.initKernel();
    printString("[Boot] IPC Router initialized!\n");

    // 3. Initialize the Scheduler
    printString("[Boot] Initializing Scheduler...\n");
    core_scheduler = scheduler.Scheduler.init();
    printString("[Boot] Scheduler initialized!\n");

    // 4. Initialize Security, IRQ, Agent, and Display subsystems
    security_manager = security.SecurityManager{};
    tap_verifier = physical_intent.PhysicalSequenceVerifier{};
    clarigggz_keychain = tee_mod.initKeychain();
    irq_router = irq_router_mod.IrqRouter.init(plic_base);
    clint_dev = plic_dev.Clint.init(clint_base);
    agent_runtime = agent_runtime_mod.AgentRuntime.init();
    _ = agent_runtime.register("spatial-planner", 4, 0) catch 0;
    _ = agent_runtime.register("vision-agent", 6, 0) catch 0;
    const tee_tag = @tagName(clarigggz_keychain.backendKind());
    printString("[Boot] Clarigggz Keychain online (TEE=");
    printString(tee_tag);
    printString(")\n");

    // 5. Initialize the Root Capability List
    printString("[Boot] Initializing Root CList...\n");
    var root_clist: capability.CList = undefined;
    capability.CList.init(&root_clist, 64, 0);
    printString("[Boot] Root CList initialized!\n");

    // 6. Create the first system thread (Primary Manager)
    printString("[Boot] Creating root thread...\n");
    const root_thread = if (comptime builtin.is_test) (allocator.create(scheduler.Thread) catch {
        printString("[Panic] Failed to create root thread\n");
        while (true) {}
    }) else blk: {
        const raw = kernel_alloc(@sizeOf(scheduler.Thread), @alignOf(scheduler.Thread)) orelse {
            printString("[Panic] Out of memory creating root thread!\n");
            while (true) {}
        };
        break :blk @as(*scheduler.Thread, @ptrCast(@alignCast(raw)));
    };
    root_thread.* = scheduler.Thread.init(0, &root_clist, null, 0x807FFFFF, 0);
    root_thread.priority = 255;
    core_scheduler.addThread(root_thread) catch {};
    printString("[Boot] Root thread created!\n");

    // 7. Create an initial system port
    printString("[Boot] Creating root port...\n");
    _ = ipc_router.createPort(0, &root_clist) catch {
        printString("[Panic] Failed to create root port\n");
        while (true) {}
    };
    printString("[Boot] Root port created!\n");

    // 8. Initialize RVV 1.0 vector unit
    printString("[Boot] Initializing RVV 1.0...\n");
    rvv.init();
    rvv.logStatus(printString);

    // 9. Load adapters (ELF blobs first, then built-in symbols)
    if (comptime builtin.os.tag == .freestanding) {
        printString("[Boot] Loading adapters...\n");
        const registry = @import("adapter_registry.zig");
        var loader: registry.Loader = .{};

        const embedded = @import("embedded_adapters.zig");
        for (embedded.blobs) |blob| {
            loader.loadElfBlob(blob.name, blob.priority, blob.uses_vectors, blob.data, &core_scheduler, &ipc_router, kernel_aspace);
        }

        if (loader.loaded_count == 0) {
            loader.loadAll(&core_scheduler, &ipc_router, kernel_aspace, &registry.builtin_descriptors);
        }

        // Bind IRQ lines to adapter ports by thread id
        for (loader.loaded[0..loader.loaded_count]) |la| {
            if (la.thread.id == 3) {
                _ = irq_router.bind(plic_dev.Plic.IRQ_TACTILE, la.port_id, protocols.input.InputPort.ProtocolID) catch {};
            }
            if (la.thread.id == 1) {
                _ = irq_router.bind(plic_dev.Plic.IRQ_VSYNC, la.port_id, protocols.display.DisplayPort.ProtocolID) catch {};
            }
            if (la.thread.id == 4) {
                _ = irq_router.bind(plic_dev.Plic.IRQ_AGENT, la.port_id, protocols.agent.AgentPort.ProtocolID) catch {};
            }
        }

        clint_dev.armTimer(0, 16_666_666);
        asm volatile ("csrs sstatus, %[sie]" : : [sie] "r" (@as(u64, 1 << 1)));
        asm volatile ("csrs sie, %[mask]" : : [mask] "r" (@as(u64, (1 << 9) | (1 << 5))));

        printString("[Boot] Adapter load complete.\n");
    }

    printString("[Boot] Entering realtime scheduler loop...\n");

    // Core Loop: priority scheduling with cooperative context switch
    while (true) {
        if (core_scheduler.schedule()) |next| {
            if (next.id != 0) {
                const prev_thread = current_thread;
                const prev_ctx = if (prev_thread) |t| &t.ctx else &scheduler_ctx;
                current_thread = next;
                scheduler.switch_context(prev_ctx, &next.ctx);
                current_thread = prev_thread;
            }
        }

        if (comptime builtin.os.tag == .freestanding) {
            irq_router.dispatchPending(&ipc_router, &core_scheduler, onAgentIrq);
        }

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

    var router = ipc_transport.Router.init(allocator);
    defer {
        for (router.ports[0..router.ports_count]) |maybe_port| {
            if (maybe_port) |port| {
                allocator.destroy(port);
            }
        }
    }

    var clist: capability.CList = undefined;
    capability.CList.initTest(&clist, allocator, 4, 1);
    defer allocator.free(clist.caps);

    const port_id = try router.createPort(1, &clist);

    clist.caps[0] = .{
        .cap_type = .ipc_endpoint,
        .rights = capability.Capability.Rights.write,
        .object_id = @as(u24, @intCast(port_id)),
        .base = 0,
        .limit = 0,
    };

    var sched = scheduler.Scheduler.init();

    const msg = protocols.ipc.Message{
        .sender_id = 1,
        .protocol_id = 42,
        .payload_len = 0,
        .capability_bits = 0,
        .payload = [_]u8{0} ** 128,
    };

    try router.deliver(&clist, 0, msg, 1, &sched);

    const port = router.ports[port_id].?;
    const delivered = port.pop().?;
    try std.testing.expectEqual(delivered.protocol_id, 42);
}
