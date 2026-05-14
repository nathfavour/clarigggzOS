# Skill: Consult Local Docs 📖

## Overview
This skill mandates the use of the locally cached Zig documentation to ensure version-accurate assistance.

## Instructions
1.  **Context**: The user has pinned this project to Zig 0.16.0.
2.  **Workflow**:
    - Before explaining language features (e.g., `for` loops, `comptime`, `struct` layouts), check `.docs/index.html`.
    - This file is updated alongside the codebase. If the codebase is 0.16.0, the docs are 0.16.0.
3.  **WIP Status**: Acknowledge that as new Zig versions release, we will perform a dual-update: the Zig compiler version and the `.docs/` content.
