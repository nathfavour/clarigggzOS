# Clarigggz OS Implementation Roadmap

Status key: `[x]` done · `[~]` partial · `[ ]` not started

## Phase 1: Bare-Metal Foundation (RISC-V K1)
- [x] **K1 Bootloader Integration**: `arch/riscv64/k1/boot.S`, `trap.S`, `switch.S`
- [x] **WFI Control**: Idle loop uses `wfi` (RISC-V) / `hlt` (x86_64)
- [x] **Vector Extension (RVV 1.0) Initialization**: Boot enables VS in `sstatus`; `core/rvv.zig` verifies VLEN
- [x] **Page Table Management**: SV39 paging with identity map and MMIO mapping in `kmain`

## Phase 2: Hexagonal Microkernel (The Core Broker)
- [x] **Capability System**: C-lists with derive, grant, and revoke
- [x] **IPC Transport**: Sync message passing with port queues and blocking send/recv
- [x] **Scheduler**: Priority queues with `switch_context` cooperative preemption
- [~] **Interrupt Routing**: Trap handler + syscall path; PLIC/CLINT → adapter delivery in progress

## Phase 3: Ports & Protocols
- [x] **DisplayPort**: Framebuffer layout and VSync event types
- [x] **InputPort**: Tactile and spatial event structures
- [x] **NeuralPort**: RVV-oriented tensor request protocol
- [x] **Runtime Syscalls**: `protocols/runtime.zig` yield, log, submit_intent stubs

## Phase 4: Adapters (User-Space Servers)
- [x] **Adapter Loader**: `core/adapter_loader.zig` spawns compositor, neural, tactile threads
- [~] **Waveguide Compositor**: Desktop demo + software blend; HW framebuffer path TODO
- [~] **Tactile ID Server**: Intent submission via `submit_intent` syscall
- [~] **Neural Engine**: RVV f16 multiply in adapter loop
- [ ] **ELF Loader**: Load externally built adapter binaries from storage

## Phase 5: Security & "Intent-to-Unlock"
- [x] **Physical Sequence Verifier**: Tap-sequence logic in `core/physical_intent.zig`
- [x] **Security Manager Wiring**: `handleTactileEvent` → `attemptUnlock` → liability log
- [x] **Liability Logger**: Ring buffer + UART emit on unlock
- [ ] **TrustZone / Secure Enclave**: Hardware-backed biometric storage

## Phase 6: Simulator Parity (x86_64)
- [x] **K1 Peripheral Mocks**: MMIO and IRQ controller mocks in `simulator/`
- [x] **End-to-End Protocol Loop**: IRQ → IPC → adapter + security unlock demo
- [ ] **RVV Emulation Support**: QEMU RVV or host-side vector mapping for neural tests
