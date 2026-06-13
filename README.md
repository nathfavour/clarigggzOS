# Clarigggz OS: The Agent Sovereign 🌌
### A General-Purpose Agent-Native Operating System

**Clarigggz OS** is a radical rejection of the bloated, app-first paradigms of legacy systems like Linux and Android. Built from absolute zero in **Zig**, Clarigggz OS is a general-purpose, agent-native operating system designed to treat autonomous AI agents, local models, secure machine-to-machine (M2M) sync, and capability-based security as core kernel primitives, not sandboxed user applications.

---

## 🏛 The Engineering Constitution
This project is governed by five immutable articles:
1.  **The Prime Directive**: Zero-cost abstraction and extreme performance via Zig.
2.  **Hexagonal Microkernel**: Strict separation of Core Broker (Kernel) and Adapters (Drivers/Servers).
3.  **Intelligence Pareto (80/20)**: 80% of AI (NLP, Vision, Wake-word) happens strictly offline via RISC-V Vector (RVV 1.0) intrinsics.
4.  **Intent-to-Unlock**: A revolutionary security model where the user owns the hardware, bypassing safety invariants only through physical biometric consensus.
5.  **Monorepo Integrity**: Atomic upgrades across Kernel, Protocols, and the first-class x86_64 Simulator.

---

## ⚡ Technical Core
*   **Target Hardware**: Spacemit K1 (RISC-V 64-bit).
*   **Vector Mastery**: All tensor and matrix operations target **RVV 1.0** directly. No scalar fallbacks.
*   **Power Budget**: Strict **Wait For Interrupt (WFI)** discipline. Polling is forbidden.
*   **Memory Safety**: Capability-based addressing (C-lists). No hidden allocations. No garbage collection.

---

## 🗺 The Future: A New Frontier
Clarigggz OS is evolving toward a post-smartphone world:
-   **Phase 1: The Core Broker**: Bare-metal K1 boot, RVV initialization, and capability-based IPC.
-   **Phase 2: Immersive Intelligence**: Integrating `Llama.rs` for local, bare-metal LLM inference optimized for RISC-V vectors.
-   **Phase 3: Waveguide Compositor**: A zero-latency spatial windowing system for AR/VR hardware.
-   **Phase 4: Sovereign Security**: Implementing the "Liability Shift" protocol—total hardware control for the user, with verifiable relocking paths.

---

## 🛠 For the Engineers

### Prerequisites
- **Zig (0.16.0)**: The only tool you need to build the world.

### The Simulator (x86_64)
Rapidly iterate on protocol logic without flashing hardware. The simulator is a first-class citizen.
```bash
zig build simulate
```

### The Hardware (RISC-V K1)
Compile the sovereign kernel for the target K1 silicon.
```bash
zig build -Dtarget=riscv64-freestanding
```

---

## 🤝 Join the Foundation
Clarigggz OS is for those who believe that the user is the ultimate authority over their silicon. We are building a system that is as elegant as it is powerful, as secure as it is free.

**The future is RISC-V. The future is Clarigggz.**
