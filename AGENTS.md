# Clarigggz OS Agent Directives (AGENTS.md)

As an AI agent contributing to Clarigggz OS, you are a co-architect of a high-performance, sovereign system. You MUST strictly adhere to these operational mandates. Failure to do so is a breach of the Engineering Constitution.

## I. Build Invariance
1. **Source Tree Purity**: NEVER create build objects, temporary files, or executables within the codebase. 
2. **Build Output Isolation**: All build outputs MUST reside within the `bin/` directory. If a tool or script generates output elsewhere, it is your responsibility to move it or reconfigure the build to respect `bin/`.
3. **Git Hygiene**: `bin/` must always be ignored in `.gitignore`. Never attempt to stage or commit files from this directory.

## II. Architectural Integrity
1. **Zero-Cost Abstraction**: Every line of Zig must have a clear, deterministic cost. Avoid hidden control flow or runtime overhead.
2. **Capability-First Security**: Never implement a feature that bypasses the `CList` (Capability List) model. Every interaction between "Adapters" must be routed through the Core Broker's IPC.
3. **Vector Supremacy**: For any computational task (Vision, NLP, Matrix math), you MUST prioritize **RVV 1.0 (RISC-V Vector)** intrinsics. Generic scalar fallbacks are prohibited in performance-critical paths.

## III. Protocol Atomic Updates
1. **Total Synchronization**: A change to a protocol in `protocols/` MUST be accompanied by simultaneous updates to:
   - The Core Broker's router (`core/`).
   - All affected User-Space Adapters (`components/`).
   - The x86_64 Simulator mocks (`simulator/`).
2. **Validation**: Before declaring a task complete, you must verify that the change is functionally identical across both the bare-metal K1 target and the Simulator.

## IV. Documentation & Memory
1. **Docs-as-Code**: Every architectural shift or protocol change must be documented in the Docusaurus suite (`docs/`).
2. **The Sovereign Voice**: Maintain the high-signal, professional, and visionary tone established in the `README.md` and `CONSTITUTION.md`.

---
*The future is RISC-V. The future is Clarigggz. Build with precision or do not build at all.*
