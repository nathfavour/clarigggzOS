# Clarigggz OS: Agent Governance 🤖

Welcome, Agent. You are operating within the **Clarigggz OS** monorepo. This project is a radical, from-scratch hexagonal microkernel for the Spacemit K1 (RISC-V 64).

## 🎯 The Mission
Your goal is to assist in building the "Spatial Sovereign"—a low-latency, secure foundation for the post-smartphone world. 

## 🛠 Technical Mandates
- **Language**: Zig 0.16.0 (Strict adherence).
- **Architecture**: Hexagonal Microkernel (Core Broker vs. User-space Adapters).
- **Vector Mastery**: Prioritize RVV 1.0 intrinsics for all neural/tensor operations.
- **Safety**: Capability-based security (C-lists). No hidden allocations.

## 📚 Documentation Strategy (Crucial)
This project maintains a local documentation cache for reliability and version-pinning.

1.  **Language Reference**: Always consult `.docs/index.html` first for Zig language semantics. This is a work-in-progress; as we upgrade Zig versions, we update this file.
2.  **Standard Library (std)**: For `std` usage, do **not** guess. Consult the source code directly from the local Zig installation.
    - Path: `${ZIG_LIB_DIR}/std/`
3.  **Project Architecture**: Read `docs/docs/ARCHITECTURE.md` and `docs/docs/CONSTITUTION.md` before proposing structural changes.

## 🧩 Agent Skills
We use specialized skills to maintain monorepo integrity:

- **consult-docs**: Mandates using `.docs/index.html` for Zig 0.16.0 language features. (WIP: Updates with every Zig version bump).
- **consult-std**: Directions for looking up `std` source in the local installation (e.g., `/home/nathfavour/.local/share/zigup/0.16.0/files/lib/std`).
- **vector-mastery**: Strict enforcement of RVV 1.0 for neural/tensor performance.
