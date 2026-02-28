# Clarigggz OS Architecture: The Hexagonal Microkernel

## 1. Philosophical Foundation
Clarigggz OS is a capability-based, hexagonal microkernel designed for the Spacemit K1 RISC-V architecture. It prioritizes zero-cost abstraction, deterministic performance, and strict hardware-software symbiosis.

## 2. Hexagonal Microkernel Design
The system follows a strict "Ports and Adapters" pattern at the kernel level:

### The Core Broker (`core/`)
- **Responsibility**: Memory management (paging), thread scheduling (RVV-aware), and IPC routing.
- **Invariant**: No hardware drivers. The kernel only understands "Capabilities" (C-lists).
- **Language**: Zig (Freestanding).

### Ports as Protocols (`protocols/`)
- Inter-process communication is governed by Zig interfaces.
- **DisplayPort**: Defines frame buffer handoffs and VSync signals.
- **InputPort**: Defines tactile, biometric, and spatial input events.
- **NeuralPort**: Defines tensor offloading to the K1's vector units.

### Adapters as Servers (`components/`)
- Every driver is a user-space "Adapter" server.
- **Isolation**: Each adapter runs in its own address space. If the `WaveguideCompositor` crashes, the `CoreBroker` restarts it.
- **Capability**: Adapters only gain access to hardware registers through kernel-granted capabilities.

## 3. The "Intent-to-Unlock" Security Model
Security is not a lock; it is a contract.
- **The Sandbox**: Default state. Enforced thermal limits and scheduling priorities.
- **The Physical Consensus**: Unlocking requires a biometric handshake (Tactile ID) + a physical sequence (e.g., specific tap pattern).
- **The Liability Shift**: Upon unlocking, the user accepts full control over the RISC-V K1's power states. The OS logs this state transition to a write-only secure enclave.

## 4. Intelligence Strategy (Pareto 80/20)
- **Local (80%)**: Pattern recognition and NLP occur on-device using Zig-native RVV 1.0 intrinsics.
- **Remote (20%)**: High-latency reasoning is proxied via encrypted tunnels only when the local Pareto-limit is reached.
- **Vector Mastery**: The `NeuralPort` protocol enforces RVV 1.0 usage for all tensor operations.

## 5. Simulation & Portability
- **The x86_64 Simulator**: A first-class citizen. Every protocol must have a "Mock Adapter" that runs on Linux.
- **Atomic Commits**: Protocol changes must be reflected in the Kernel, Adapter, and Simulator simultaneously.
