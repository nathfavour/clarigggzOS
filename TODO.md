# Clarigggz OS Implementation Roadmap

Status key: `[x]` done · `[~]` partial · `[ ]` not started

## Phase 1: Bare-Metal Foundation (RISC-V K1)
- [x] **K1 Bootloader Integration**: `arch/riscv64/k1/boot.S`, `trap.S`, `switch.S`
- [x] **WFI Control**: Idle loop uses `wfi` (RISC-V) / `hlt` (x86_64)
- [ ] **Vector Extension (RVV 1.0) Initialization**: Enable V-extension in `mstatus` and verify VLEN at boot
- [x] **Page Table Management**: SV39 paging with identity map and MMIO mapping in `kmain`

## Phase 2: Hexagonal Microkernel (The Core Broker)
- [x] **Capability System**: C-lists with derive, grant, and revoke
- [x] **IPC Transport**: Sync message passing with port queues and blocking send/recv
- [~] **Scheduler**: Priority queues and RVV-aware context struct; assembly context switch TODO
- [~] **Interrupt Routing**: Trap handler scaffold; PLIC/CLINT delivery to adapters in progress

## Phase 3: Ports & Protocols
- [x] **DisplayPort**: Framebuffer layout and VSync event types
- [x] **InputPort**: Tactile and spatial event structures
- [x] **NeuralPort**: RVV-oriented tensor request protocol

## Phase 4: Adapters (User-Space Servers)
- [~] **Waveguide Compositor**: Desktop demo and software alpha blend; RVV blend and HW path TODO
- [~] **Tactile ID Server**: Adapter scaffold; IPC integration TODO
- [ ] **Agent Runtime**: Load adapters as isolated address spaces from kernel
- [ ] **Llama.rs Integration**: Offline NLP parsing using RVV 1.0 intrinsics

## Phase 5: Security & "Intent-to-Unlock"
- [ ] **TrustZone Implementation**: Software-defined secure enclave for biometric data
- [~] **Physical Sequence Verifier**: Tap-sequence logic in `core/physical_intent.zig`
- [ ] **Liability Logger**: Write-only state transitions for "Unlocked" status

## Phase 6: Simulator Parity (x86_64)
- [x] **K1 Peripheral Mocks**: MMIO and IRQ controller mocks in `simulator/`
- [~] **End-to-End Protocol Loop**: IRQ → IPC → adapter demo in `zig build simulate`
- [ ] **RVV Emulation Support**: QEMU RVV or host-side vector mapping for neural adapter tests
