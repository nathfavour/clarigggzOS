<p align="center">
  <strong>Clarigggz OS</strong><br/>
  The universal realtime, efficient agentic operating system<br/>
  for the post-smartphone world — smart glasses, wearables, and spatial devices.
</p>

<p align="center">
  <code>Zig 0.16.0</code> · <code>RISC-V 64 (RVV 1.0)</code> · <code>Hexagonal Microkernel</code> · <code>Capability Security</code>
</p>

---

## Why Clarigggz

Legacy operating systems were built for apps, touchscreens, and background daemons. The next generation of devices — **70 g smart glasses**, hearables, ambient sensors, and spatial computers — need something different:

| Requirement | Legacy OS | Clarigggz OS |
|---|---|---|
| Latency | Best-effort scheduling | **Deterministic realtime paths** for display, vision, and input |
| Intelligence | Cloud-first, battery-heavy | **80% on-device** via RVV 1.0; remote only when local limits are hit |
| Security | App sandboxes | **Capability lists (C-lists)** + physical intent consensus |
| Architecture | Monolithic kernel + drivers | **Hexagonal microkernel**: Core Broker, protocol ports, user-space adapters |
| Development | Hardware-only iteration | **First-class x86_64 simulator** with digital-twin peripherals |

Clarigggz OS treats **autonomous agents, local models, M2M sync, and capability security** as kernel primitives — not bolted-on userland services.

> **Pitch:** A universal, realtime, efficient agentic OS — lean enough for face-worn silicon, sovereign enough for the user to own their hardware.

---

## Architecture at a Glance

The system follows a strict **Ports & Adapters** (hexagonal) pattern. The Core Broker never touches hardware directly; adapters earn access through capabilities.

```
┌─────────────────────────────────────────────────────────────┐
│                   User-Space Adapters                       │
│   Compositor          Tactile ID           Neural Engine    │
│   (DisplayPort)       (InputPort)          (NeuralPort)     │
└────────────┬─────────────────┬──────────────────┬───────────┘
             │ IPC             │ IPC              │ IPC
┌────────────▼─────────────────▼──────────────────▼───────────┐
│                      Protocol Ports                         │
│              display · input · neural · ipc                 │
└────────────┬────────────────────────────────────────────────┘
             │ syscalls (ecall)
┌────────────▼────────────────────────────────────────────────┐
│                    Core Broker (kernel)                     │
│   SV39 paging · scheduler · C-lists · IPC router · security │
└─────────────────────────────────────────────────────────────┘
```

### Core subsystems

| Subsystem | Role | Location |
|---|---|---|
| **Core Broker** | Memory, scheduling, capabilities, IPC — no drivers | `core/` |
| **Protocol ports** | Typed contracts between kernel and adapters | `protocols/` |
| **Adapters** | Isolated user-space servers (compositor, biometrics, inference) | `components/` |
| **Simulator** | x86_64 digital twin (MMIO, IRQ, protocol parity) | `simulator/` |
| **Arch glue** | Boot, traps, context switch, linker scripts | `arch/` |

Deep dives: [`ARCHITECTURE.md`](ARCHITECTURE.md) · [`docs/docs/ARCHITECTURE.md`](docs/docs/ARCHITECTURE.md) · [`docs/docs/CONSTITUTION.md`](docs/docs/CONSTITUTION.md)

---

## Design Principles

1. **Agent-native by default** — Agents communicate over capability-checked IPC, not opaque POSIX pipes.
2. **Realtime where it matters** — Display composition, camera ingest, and vector math run on predictable, high-priority paths.
3. **Vector mastery** — All tensor work targets **RISC-V Vector (RVV 1.0)**; scalar fallbacks are bootstrap-only.
4. **Intent-to-unlock** — Security is a contract: sandbox by default; full hardware control only after biometric + physical sequence consensus.
5. **Zero hidden allocation** — Critical kernel paths use pre-allocated buffers and deterministic heaps.
6. **WFI discipline** — Idle cores sleep via `wfi`; polling loops are forbidden on battery-constrained devices.
7. **Simulator parity** — Protocol changes land in kernel, adapters, and simulator together.

---

## Repository Layout

```
clarigggzOS/
├── core/              # Core Broker: paging, scheduler, IPC, capabilities, security
├── protocols/         # DisplayPort, InputPort, NeuralPort, IPC message types
├── components/        # User-space adapters (compositor, tactile_id, neural)
├── simulator/         # x86_64 digital twin for rapid protocol iteration
├── arch/              # riscv64/k1 and x86_64 boot & trap entry
├── docs/docs/         # Constitution and canonical architecture notes
├── .agents/skills/    # Agent skills (Zig docs, std, RVV enforcement)
├── build.zig          # Build graph: kernel, bin, components, simulate, iso
└── AGENTS.md          # Instructions for AI agents working in this repo
```

---

## Build & Run

### Prerequisites

| Tool | Version | Notes |
|---|---|---|
| **Zig** | **0.16.0** (pinned) | Freestanding + host builds |
| **QEMU** | `riscv64` | Bare-metal bring-up on `virt` machine |
| **llvm-objcopy** | — | Raw binary extraction (`zig build bin`) |
| **grub-mkrescue** | optional | ISO packaging only |

### Quick start (simulator)

Fastest path to see the system boot, route an IRQ → IPC event, and render the desktop environment:

```bash
zig build simulate
```

### Kernel (RISC-V freestanding)

```bash
# Build kernel ELF
zig build kernel

# Raw binary for QEMU / flash
zig build bin -Dhardware=qemu_virt      # QEMU virt UART @ 0x10000000
zig build bin -Dhardware=spacemit_k1    # SpacemiT K1 UART @ 0xD8000000
```

### QEMU (RISC-V virt)

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

### Other build targets

```bash
zig build components    # User-space adapters
zig build test          # Unit tests (host)
zig build iso           # Bootable ISO (requires grub-mkrescue)
```

Install artifacts land in `zig-out/bin/` (kernel also mirrored under `bin/` per build config).

---

## Implementation Status

Honest snapshot of what exists today vs. what is planned.

| Area | Status | Notes |
|---|---|---|
| RISC-V boot & UART | ✅ | `arch/riscv64/k1/`, comptime hardware register maps |
| SV39 paging | ✅ | Identity map + MMIO mapping in `kmain` |
| Buddy allocator | ✅ | Deterministic kernel heap |
| Capability lists | ✅ | 128-bit caps, derive/grant/revoke |
| IPC router | ✅ | Sync send/recv blocking, port queues |
| Priority scheduler | ✅ | Cooperative `riscv_switch_context` + priority queues |
| Syscall dispatcher | ✅ | ecall trap path, yield/ipc/submit_intent syscalls |
| Physical intent | ✅ | Tap-sequence verifier wired to SecurityManager |
| Protocol ports | ✅ | Display, Input, Neural, IPC + `protocols/runtime.zig` |
| Adapter loader | ✅ | Spawns compositor, neural, tactile as kernel threads |
| Compositor adapter | ✅ | Kernel-threaded adapter with yield loop |
| Neural adapter | ✅ | RVV f16 multiply + yield loop |
| Tactile ID adapter | ✅ | Intent-to-unlock via `submit_intent` syscall |
| x86_64 simulator | ✅ | IRQ → IPC → security unlock demo |
| Agent runtime / Llama | ⬜ | Phase 2 roadmap |
| ELF adapter loader | ⬜ | Load external adapter binaries from storage |
| Waveguide compositor (HW) | ⬜ | Phase 3 roadmap |

See [`TODO.md`](TODO.md) for the phased roadmap.

---

## Roadmap

| Phase | Focus | Outcome |
|---|---|---|
| **1 — Core Broker** | Boot, paging, IPC, scheduler, capabilities | Sovereign kernel on K1 silicon |
| **2 — Immersive Intelligence** | Local LLM inference (RVV-optimized) | Agents run offline on-device |
| **3 — Waveguide Compositor** | Zero-latency spatial windowing | AR/smart-glass display pipeline |
| **4 — Sovereign Security** | Liability shift, secure enclave logging | User-owned hardware unlock path |

---

## Target Hardware

Primary silicon: **SpacemiT K1** — RISC-V 64 with **RVV 1.0** (256-bit vectors).

The kernel is hardware-agnostic at the protocol layer: adapters bind to MMIO via capabilities, so the same Core Broker can target QEMU `virt`, K1 dev kits, or future smart-glass boards without rewriting intelligence or security logic.

---

## For AI Agents & Contributors

This repo is designed for human and agent collaboration.

- Read **`AGENTS.md`** before structural changes.
- Use **`.agents/skills/`** for Zig 0.16.0 semantics, `std` lookups, and RVV enforcement.
- Consult **`.docs/index.html`** for pinned language reference (do not guess Zig APIs).

```bash
# Agent skill locations
.agents/skills/consult-docs/     # Zig 0.16.0 language reference
.agents/skills/consult-std/      # std library source verification
.agents/skills/vector-mastery/  # RVV 1.0 tensor policy
```

---

## License

GNU General Public License v3.0 — see [`LICENSE`](LICENSE).

---

<p align="center">
  <sub>The future is RISC-V. The future is agentic. The future is Clarigggz.</sub>
</p>
