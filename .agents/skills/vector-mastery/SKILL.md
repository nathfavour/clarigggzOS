# Skill: RISC-V Vector Mastery ⚡

## Overview
Clarigggz OS is a first-class citizen for RISC-V Vector (RVV 1.0) operations.

## Instructions
1.  **Optimization**: When implementing neural or matrix operations, always look for an RVV 1.0 implementation pathway.
2.  **Intrinsics**: Target `@import("std").Target.riscv.featureSet(&.{.v})` in `build.zig`.
3.  **Constraint**: Avoid scalar fallbacks in `components/neural/` unless absolutely necessary for bootstrapping.
