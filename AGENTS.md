# Clarigggz OS: Agent Governance 🤖

Welcome, Agent. You are operating within the **Clarigggz OS** monorepo — a from-scratch hexagonal microkernel for the SpacemiT K1 (RISC-V 64) and the x86_64 simulator.

## 🎯 The Mission

Build the **universal realtime, efficient agentic operating system** — a low-latency, capability-secure foundation for smart glasses, wearables, and spatial devices in the post-smartphone world.

## 🛠 Technical Mandates

- **Language**: Zig 0.16.0 (strict adherence).
- **Architecture**: Hexagonal microkernel (Core Broker vs. user-space adapters).
- **Vector mastery**: Prioritize RVV 1.0 intrinsics for all neural/tensor operations.
- **Safety**: Capability-based security (C-lists). No hidden allocations.

## 📚 Documentation Strategy (Crucial)

This project maintains a local documentation cache for reliability and version-pinning.

1. **Language reference**: Always consult `.docs/index.html` first for Zig language semantics. Updated alongside compiler version bumps.
2. **Standard library (`std`)**: Do **not** guess. Consult source at `${ZIG_LIB_DIR}/std/`.
3. **Project architecture**: Read `ARCHITECTURE.md`, `docs/docs/ARCHITECTURE.md`, and `docs/docs/CONSTITUTION.md` before proposing structural changes.
4. **Implementation status**: Check `README.md` and `TODO.md` for honest progress before marking work complete.

## 🧩 Agent Skills

- **consult-docs**: Mandates using `.docs/index.html` for Zig 0.16.0 language features.
- **consult-std**: Directions for looking up `std` source in the local installation (e.g. `/home/nathfavour/.local/share/zigup/0.16.0/files/lib/std`).
- **vector-mastery**: Strict enforcement of RVV 1.0 for neural/tensor performance.
