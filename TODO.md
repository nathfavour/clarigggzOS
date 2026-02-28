# Clarigggz OS Implementation Roadmap

## Phase 1: Bare-Metal Foundation (RISC-V K1)
- [ ] **K1 Bootloader Integration**: Implement `arch/riscv64/k1/boot.S` to handle early HART initialization.
- [ ] **WFI Control**: Implement the "Prime Directive" power management (Wait For Interrupt) in the idle loop.
- [ ] **Vector Extension (RVV 1.0) Initialization**: Enable V-extension in `mstatus` and verify vector length (VLEN).
- [ ] **Page Table Management**: Implement SV39 or SV48 paging for isolated user-space "Adapters".

## Phase 2: Hexagonal Microkernel (The Core Broker)
- [ ] **Capability System**: Implement C-lists for granular resource access (Memory, IRQs, IPC).
- [ ] **IPC Transport**: High-performance, zero-copy message passing between Adapters.
- [ ] **Scheduler**: RVV-aware context switching (saving/restoring vector registers only when necessary).
- [ ] **Interrupt Routing**: Core Broker to Adapter event delivery.

## Phase 3: Ports & Protocols
- [ ] **DisplayPort**: Define the waveguide compositor interface.
- [ ] **InputPort**: Define the "Tactile ID" and spatial event structures.
- [ ] **NeuralPort**: Define the RVV-optimized tensor offloading protocol.

## Phase 4: Adapters (User-Space Servers)
- [ ] **Waveguide Compositor**: Initial framebuffer server.
- [ ] **Tactile ID Server**: Biometric verification process.
- [ ] **Llama.rs Integration**: Offline NLP parsing using RVV 1.0 intrinsics.

## Phase 5: Security & "Intent-to-Unlock"
- [ ] **TrustZone Implementation**: Software-defined secure enclave for biometric data.
- [ ] **Physical Sequence Verifier**: Logic for "Physical Intent" (e.g., specific tap sequences).
- [ ] **Liability Logger**: Write-only state transitions for "Unlocked" status.

## Phase 6: Simulator Parity (x86_64)
- [ ] **K1 Peripheral Mocks**: Mock IRQ controller and UART for the simulator.
- [ ] **RVV Emulation Support**: Integration with `qemu-riscv64` or native RVV-to-AVX512 mapping for simulation.
