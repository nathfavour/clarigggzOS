# Clarigggz OS: The Engineering Constitution

### The universal realtime, efficient agentic operating system

**Clarigggz OS** is a from-scratch, agent-native operating system built in **Zig 0.16.0**. It rejects app-first paradigms in favor of a hexagonal microkernel where autonomous agents, local models, secure machine-to-machine sync, and capability security are kernel primitives — not sandboxed user applications.

Target devices: smart glasses, wearables, spatial computers, and any face-worn or ambient form factor that demands **deterministic latency**, **on-device intelligence**, and **user-owned hardware**.

---

## The Five Articles

1. **The Prime Directive** — Zero-cost abstraction and extreme performance via Zig.
2. **Hexagonal Microkernel** — Strict separation of Core Broker (kernel) and Adapters (user-space servers).
3. **Intelligence Pareto (80/20)** — 80% of AI (NLP, vision, wake-word) runs offline via RISC-V Vector (RVV 1.0) intrinsics; remote reasoning only when local limits are reached.
4. **Intent-to-Unlock** — Security is a contract: sandbox by default; full hardware control only after biometric and physical sequence consensus.
5. **Monorepo Integrity** — Atomic upgrades across kernel, protocols, adapters, and the first-class x86_64 simulator.

---

## Technical Core

| Mandate | Detail |
|---|---|
| **Language** | Zig 0.16.0 (pinned) |
| **Target silicon** | SpacemiT K1 (RISC-V 64, RVV 1.0) |
| **Vector policy** | RVV 1.0 for all tensor work; scalar fallbacks are bootstrap-only |
| **Power** | WFI discipline in idle paths; polling forbidden |
| **Memory** | Capability-based addressing (C-lists); no hidden allocations; no GC |

---

## Roadmap Phases

| Phase | Focus |
|---|---|
| **1 — Core Broker** | Bare-metal boot, SV39 paging, capability IPC, scheduler |
| **2 — Immersive Intelligence** | Local LLM inference optimized for RVV |
| **3 — Waveguide Compositor** | Zero-latency spatial windowing for AR optics |
| **4 — Sovereign Security** | Liability shift protocol and verifiable relock paths |

---

## Build Commands

```bash
zig build simulate                          # x86_64 digital twin (fastest iteration)
zig build kernel                            # RISC-V freestanding kernel ELF
zig build bin -Dhardware=qemu_virt           # Raw binary for QEMU virt
zig build bin -Dhardware=spacemit_k1          # Raw binary for SpacemiT K1
zig build test                              # Host unit tests
```

---

## For Contributors and Agents

Read [`ARCHITECTURE.md`](../../ARCHITECTURE.md), [`AGENTS.md`](../../AGENTS.md), and [`.agents/skills/`](../../.agents/skills/) before proposing structural changes.

**The future is RISC-V. The future is agentic. The future is Clarigggz.**
