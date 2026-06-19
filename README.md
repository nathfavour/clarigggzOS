# Clarigggz OS: The Spatial Sovereign 🌌
### A Bare-Metal, Agent-Native Operating System for Smart Glasses

**Clarigggz OS** is a hyper-lean, bare-metal, context-aware, agentic-first operating system designed specifically for low-latency smart glasses (70-gram face-worn form factors). Built entirely in **Zig**, it implements an Asymmetric Multiprocessing (AMP) microkernel architecture optimizing physical resource limits of the **SpacemiT K1 (RISC-V 64 / RVA22)** SoC.

---

## 🏛 Core Architectural Principles

1.  **Asymmetric Multiprocessing (AMP):**
    *   **High-Speed Monolithic Pipeline:** privileged kernel space execution cluster for display composition, camera frame-capture, and matrix calculations utilizing 256-bit RISC-V Vector Extensions (RVV 1.0).
    *   **Isolated Agent Workspace:** non-privileged, isolated microkernel-style execution spaces running high-level cooperative agent logic. A crash in the agent workspace cannot disrupt camera or display tracking loops.
2.  **Zero-Allocation Runtime:** Zero hidden allocations or global state. Dynamic memory demands must explicitly ingest fixed-buffer or page allocators.
3.  **Strict Power & Thermal Discipline:** Avoid polling loops; utilize CPU-level `WFI` (Wait For Interrupt) to save battery and reduce thermal output on face-worn devices.
4.  **Capability-Based Security:** Fine-grained access control lists (C-lists) governing memory regions, physical intent consensus, and inter-process communication.

---

## 🛠 Emulation and Bare-Metal Execution

Clarigggz OS supports testing kernel systems via QEMU side-by-side with target SpacemiT hardware.

### Prerequisites

*   **Zig Toolchain (0.16.0 / 0.17.0-dev)**
*   **QEMU (riscv64)**
*   **llvm-objcopy** (included with standard compiler toolchains)

### Build Options

By default, compiling the kernel targets `riscv64-freestanding` using the `.medany` code model.

*   **Generate raw binary `clarigggz.bin` for QEMU virt:**
    ```bash
    zig build bin -Dhardware=qemu_virt
    ```
*   **Generate raw binary `clarigggz.bin` for SpacemiT K1:**
    ```bash
    zig build bin -Dhardware=spacemit_k1
    ```

### Running on QEMU

Run the compiled kernel inside QEMU's RISC-V Virt Sandbox:

```bash
qemu-system-riscv64 \
    -M virt \
    -cpu rv64 \
    -smp 8 \
    -m 2G \
    -bios default \
    -kernel zig-out/bin/clarigggz.bin \
    -nographic \
    -serial mon:stdio
```

---

## 🏛 Subsystems Roadmap

*   [x] **Buddy Allocator & Virtual Paging:** Sv39 3-level page table setup.
*   [x] **Hardware Register Map:** Zero-cost compile-time MMIO hardware mappings.
*   [x] **16550A UART Driver:** Low-level console logger mapped to virt/physical interfaces.
*   [x] **Priority Scheduler & IPC Router:** Thread context switcher and capability-bound messaging.
*   [x] **Simulator Digital Twin:** Local x86 simulator for protocol testing (`zig build simulate`).
