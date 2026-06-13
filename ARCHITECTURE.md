# Clarigggz OS: Sovereign Architecture Manual 🌌
### A General-Purpose Agent-Native Operating System

Clarigggz OS is a sovereign, agent-native, capability-based operating system written in Zig 0.16.0. It is built to bypass the legacy app-first paradigms of mainstream operating systems (Android, iOS, Linux) and target a future where autonomous AI agents, local models, secure machine-to-machine (M2M) protocols, and capability security are built directly into the kernel primitives.

---

## 1. Philosophical Foundation

### 1.1 The Hardware Velocity Trap
Physical hardware is bound by physical supply chains, fabrication, and thermal limits. Clarigggz OS treats hardware as a **black box commodity**, enabling the system to run on any single-board computer, developer kit, or smart frame, while the kernel remains the sovereign environment defining the intelligence and security layers.

### 1.2 Hexagonal Architecture (Ports & Adapters)
The kernel adheres to a strict hexagonal microkernel model, dividing code into three roles:
1.  **Core Broker (`core/`)**: The kernel core. Contains zero hardware drivers. Manages memory, scheduling, capabilities, and IPC.
2.  **Ports (`protocols/`)**: Strict interface contracts (e.g. Display, Input, Neural) defined via Zig modules.
3.  **Adapters (`components/`)**: Isolated user-space servers (e.g. Waveguide Compositor, Tactile ID, Neural Engine) that communicate with the Core Broker through Capability-checked IPC.

```
       +---------------------------------------------+
       |            User-Space Adapters              |
       |  [Compositor]     [Tactile ID]   [Neural]   |
       +-------+----------------+--------------+-----+
               |                |              |
               v (IPC)          v (IPC)        v (IPC)
       +-------+----------------+--------------+-----+
       |              Protocols / Ports              |
       |  [DisplayPort]    [InputPort]  [NeuralPort] |
       +-------+----------------+--------------+-----+
               |                |              |
               +----------------+--------------+
                                |
                                v (Syscalls)
       +------------------------+--------------------+
       |            Core Broker (Microkernel)        |
       |  [Memory/Paging]   [Scheduler]   [C-Lists]  |
       +---------------------------------------------+
```

---

## 2. Core Broker Subsystems

### 2.1 SV39 Virtual Memory Paging
*   **Virtual Address Space:** Maps the standard RISC-V SV39 virtual memory layout (39-bit virtual addresses containing three 9-bit VPN indexes and a 12-bit offset).
*   **Dynamic Allocation:** Mapping a page automatically walks the table and allocates aligned 4KB page directories for intermediate level tables (`VPN[2]` and `VPN[1]`).
*   **Address Spaces:** Enforces process isolation. If a user-space adapter faults or crashes, its virtual memory space is torn down and cleaned up recursively without leaking page table directories in the Core Broker.
*   **Translation:** Handled via SV39 tables mapping 4KB standard pages, 2MB huge-pages, and 1GB mega-pages.

### 2.2 Capability-Based Security (C-Lists)
Every operation in user-space is authorized by a capability stored in a thread's Capability List (C-List). Capabilities are 128-bit cache-aligned primitives:
*   **CapType:** `none`, `memory` (physical range), `ipc_endpoint` (port access), `irq` (hardware interrupts), `device` (MMIO ranges).
*   **Derivation:** Users can derive child capabilities restricting boundaries or rights (e.g. `read`-only subsets of `read-write` memory).
*   **Delegation & Revocation:** Threads can delegate capabilities using `grant` (requires the `grant` permission) or clear them using `revoke`.

### 2.3 Priority-Based Scheduler
*   **Queues:** Manages threads across 4 priorities (`0` highest, `3` lowest).
*   **State Machine:**
    *   `ready`: Ready to be scheduled.
    *   `running`: Currently executing on the HART.
    *   `blocked`: Waiting for an event (IPC send/recv, IRQ).
    *   `terminated`: Cleaned up.
*   **RVV Optimization:** Context switching only saves/restores the Spacemit K1's vector registers (v0-v31, vtype, vl, vstart) for threads flagged with `uses_vectors = true`.

### 2.4 Synchronized Blocking IPC
All inter-process communication is handled via message passing through ports:
*   **Sync Mechanics:**
    *   When sending to a full port, the sender thread blocks (`WaitReason.ipc_send`) on the target port ID.
    *   When receiving from an empty port, the receiver thread blocks (`WaitReason.ipc_recv`) on the target port ID.
    *   Writing to a port automatically unblocks any waiting receivers. Popping from a port unblocks any waiting senders.
*   **Zero-Copy Design:** The kernel handles capability verification and routes messages directly through kernel-managed descriptors.

### 2.5 System Call Dispatcher
The `ecall` interface handles transition between user-mode and supervisor-mode.
*   `Syscall.ipc_send`: Sends an IPC message via a capability index.
*   `Syscall.ipc_recv`: Receives an IPC message into a thread's local buffer.
*   `Syscall.yield`: Relinquishes CPU slice.
*   `Syscall.get_cap`: Retrieves capability details.
*   `Syscall.log`: Emits debugging messages to the system logger.

---

## 3. Protocols & User-Space Adapters

### 3.1 Waveguide Compositor
*   **Protocol:** `DisplayPort` defines framebuffer layouts and hardware VSync events.
*   **Functionality:** Alpha blends spatial overlays. Targets Spacemit K1's RVV 1.0 vectors to achieve high-performance spatial composition.

### 3.2 Tactile ID Server
*   **Protocol:** `InputPort` delivers tactile tapping coordinates and biometric data.
*   **Security:** Decodes physical tapping sequences for "Intent-to-Unlock" biometric validation.

### 3.3 Neural Accelerator
*   **Protocol:** `NeuralPort` manages tensor workloads.
*   **Optimization:** Harnesses RISC-V Vector (RVV 1.0) intrinsics. The implementation bypasses scalar loops to achieve deterministic inference directly in user-space.

---

## 4. Engineering Invariants & Mandates

1.  **Zero Allocation In Core Pathways:** The Core Broker uses pre-allocated buffers and a deterministic memory heap layout. No heap allocations occur in critical scheduling or IPC pathways.
2.  **Wait For Interrupt (WFI) Discipline:** In the idle scheduling loop, the Core Broker puts the RISC-V CPU into low-power states via `wfi` instructions. Polling loops are strictly forbidden.
3.  **Simulator Parity:** The x86_64 simulator provides a complete digital twin, mocking MMIO registers and Interrupt Controllers (`irq_controller.zig`, `mmio.zig`) to test microkernel mechanics without hardware.
4.  **Zig 0.16.0 Compatibility:** Direct alignment with the standard library allocations and compilation options.
