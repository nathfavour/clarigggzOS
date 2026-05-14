# Skill: Consult Std Library 🔍

## Overview
Since the standard library documentation is often generated dynamically, agents must consult the source code directly for accuracy.

## Instructions
1.  **Locate**: Use `zig env` to find the `std_dir` (currently `/home/nathfavour/.local/share/zigup/0.16.0/files/lib/std`).
2.  **Verify**: If you are unsure about an API (e.g., `std.ArrayList`, `std.mem.Allocator`), use `grep_search` or `read_file` on the local standard library files.
3.  **Strictness**: Do not rely on training data for `std` APIs as they change frequently in Zig.
