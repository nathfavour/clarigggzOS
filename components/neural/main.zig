const std = @import("std");
const protocols = @import("protocols");
const NeuralPort = protocols.neural.NeuralPort;

// Disable threaded IO dependencies for freestanding targets
pub const std_options_debug_threaded_io: ?*anyopaque = null;


/// Neural Accelerator Server: RISC-V Vector Optimized Tensor Operations.
/// This adapter runs on user-space with privileged access to RVV 1.0 extensions.
pub fn main() !void {
    // 1. Initialize Neural Engine
    var a = [_]f16{1.0} ** 64;
    var b = [_]f16{2.0} ** 64;
    var out = [_]f16{0.0} ** 64;

    // 2. Main Event Loop: Listen for tensor requests (NeuralPort.Request)
    while (true) {
        // Matmul using RVV 1.0
        matmulRVV(&a, &b, &out);
    }
}

/// Neural Engine: RVV 1.0 MatMul (Freestanding RISC-V Assembly Demonstration)
pub fn matmulRVV(a: []const f16, b: []const f16, out: []f16) void {
    const len = @min(a.len, @min(b.len, out.len));
    if (len == 0) return;

    // In a real Spacemit K1 environment, we configure the vector engine
    // and process vectors of size VLEN (e.g. 128-bit or 256-bit).
    // The following demonstrates inline assembly for RVV 1.0 setup if built for RISC-V.
    if (comptime @import("builtin").cpu.arch == .riscv64) {
        var remaining = len;
        var offset: usize = 0;
        while (remaining > 0) {
            // Set vector length for 16-bit elements (f16)
            var vl: usize = undefined;
            asm volatile (
                "vsetvli %[vl], %[remaining], e16, m1, ta, ma"
                : [vl] "=r" (vl)
                : [remaining] "r" (remaining)
            );

            // Vector load top and bottom vectors
            asm volatile (
                \\vle16.v v8, (%[ptr_a])
                \\vle16.v v16, (%[ptr_b])
                \\vfmul.vv v24, v8, v16
                \\vse16.v v24, (%[ptr_out])
                :
                : [ptr_a] "r" (a.ptr + offset),
                  [ptr_b] "r" (b.ptr + offset),
                  [ptr_out] "r" (out.ptr + offset)
            );

            remaining -= vl;
            offset += vl;
        }
    } else {
        // Fallback for simulator targets
        for (0..len) |i| {
            out[i] = a[i] * b[i];
        }
    }
}

export fn _start() callconv(.c) noreturn {
    _ = main() catch {};
    while (true) {}
}
