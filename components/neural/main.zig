const std = @import("std");
const protocols = @import("protocols");
const runtime = protocols.runtime;

pub const std_options_debug_threaded_io: ?*anyopaque = null;

fn adapterMain() void {
    runtime.log("neural-engine: RVV tensor adapter online");

    var a = [_]f16{1.0} ** 64;
    var b = [_]f16{2.0} ** 64;
    var out = [_]f16{0.0} ** 64;

    var loops: usize = 0;
    while (loops < 100) : (loops += 1) {
        matmulRVV(&a, &b, &out);
        runtime.yield();
    }
}

pub export fn clarigggz_neural_entry() callconv(.c) noreturn {
    adapterMain();
    while (true) {
        runtime.yield();
    }
}

pub fn matmulRVV(a: []const f16, b: []const f16, out: []f16) void {
    const len = @min(a.len, @min(b.len, out.len));
    if (len == 0) return;

    if (comptime @import("builtin").cpu.arch == .riscv64) {
        var remaining = len;
        var offset: usize = 0;
        while (remaining > 0) {
            var vl: usize = undefined;
            asm volatile (
                "vsetvli %[vl], %[remaining], e16, m1, ta, ma"
                : [vl] "=r" (vl)
                : [remaining] "r" (remaining)
            );
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
        for (0..len) |i| {
            out[i] = a[i] * b[i];
        }
    }
}

const builtin = @import("builtin");
const config = @import("config");

fn startShim() callconv(.c) noreturn {
    clarigggz_neural_entry();
}

fn threadYieldEcall() callconv(.c) void {
    asm volatile (
        \\li a0, 3
        \\ecall
        ::: .{ .memory = true }
    );
}

comptime {
    if (builtin.os.tag == .freestanding and !config.kernel_adapter) {
        @export(&startShim, .{ .name = "_start", .linkage = .strong });
        @export(&threadYieldEcall, .{ .name = "clarigggz_thread_yield", .linkage = .weak });
    }
}

pub fn main() !void {
    adapterMain();
}
