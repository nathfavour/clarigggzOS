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
- [x] **Interrupt Routing**: PLIC/CLINT MMIO, IRQ router → adapter IPC delivery

## Phase 3: Ports & Protocols
- [x] **DisplayPort**: Framebuffer layout and VSync event types
- [x] **InputPort**: Tactile and spatial event structures
- [x] **NeuralPort**: RVV-oriented tensor request protocol
- [x] **Runtime Syscalls**: `protocols/runtime.zig` yield, log, submit_intent stubs

## Phase 4: Adapters (User-Space Servers)
- [x] **Adapter Loader**: `core/adapter_loader.zig` spawns compositor, neural, tactile threads
- [x] **Waveguide Compositor**: HW framebuffer at `0x81000000` + desktop fallback on host
- [x] **Tactile ID Server**: Intent submission via `submit_intent` syscall
- [x] **Neural Engine**: RVV f16 multiply in adapter loop
- [x] **ELF Loader**: `core/elf_loader.zig` + `zig build embed-adapters` blob staging
- [x] **Agent Runtime Adapter**: `components/agent/main.zig` + `core/agent_runtime.zig` tick scheduler

## Phase 5: Security & "Intent-to-Unlock"
- [x] **Physical Sequence Verifier**: Tap-sequence logic in `core/physical_intent.zig`
- [x] **Security Manager Wiring**: `handleTactileEvent` → `attemptUnlock` → liability log
- [x] **Liability Logger**: Ring buffer + UART emit on unlock
- [~] **TrustZone / Secure Enclave**: Write-only MMIO enclave at `0x10001000` (software stub; HW TEE pending)

## Phase 6: Simulator Parity (x86_64)
- [x] **K1 Peripheral Mocks**: MMIO and IRQ controller mocks in `simulator/`
- [x] **End-to-End Protocol Loop**: IRQ → IPC → adapter + security unlock demo
- [x] **Agent / Enclave / Framebuffer Demos**: Simulator exercises new Phase 2 subsystems
- [ ] **RVV Emulation Support**: QEMU RVV or host-side vector mapping for neural tests
