# Clarigggz OS Monorepo

## Overview
Clarigggz OS is a high-performance, capability-based microkernel built for the Spacemit K1 RISC-V architecture. This repository contains the kernel, protocols, user-space components, and an x86_64 simulator.

### Architecture
See [ARCHITECTURE.md](ARCHITECTURE.md) for a detailed breakdown of the Hexagonal Microkernel design.

## Project Structure
- `core/`: Microkernel (The Core Broker).
- `protocols/`: Zig protocol definitions for IPC and hardware interaction.
- `components/`: User-space drivers and servers (Adapters).
- `simulator/`: An x86_64 Linux-based simulation environment.
- `arch/`: Architecture-specific code (RISC-V K1).

## Getting Started

### Prerequisites
- [Zig](https://ziglang.org/) (latest master or stable 0.13.0).

### Running the Simulator
Rapidly iterate and test protocols on your development machine.
```bash
zig build simulate
```

### Building for RISC-V K1
Compile the microkernel for the target hardware.
```bash
zig build -Dtarget=riscv64-freestanding
```

## Engineering Constitution
This project adheres to the Clarigggz OS Engineering Constitution, mandating zero-cost abstraction, compile-time supremacy, and strict hardware-software symbiosis.
