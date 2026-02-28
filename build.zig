const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Set the install prefix to 'bin/' as mandated by AGENTS.md
    b.install_path = "bin";

    // --- Modules ---
    const protocols_module = b.addModule("protocols", .{
        .root_source_file = b.path("protocols/root.zig"),
    });

    // --- Clarigggz Microkernel (RISC-V K1) ---
    const kernel_exe = b.addExecutable(.{
        .name = "clarigggz-kernel",
        .root_source_file = b.path("core/main.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .riscv64,
            .os_tag = .freestanding,
            .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv64 }, 
            .cpu_features_add = std.Target.riscv.featureSet(&.{.v}), // Enable RVV 1.0
        }),
        .optimize = optimize,
    });
    kernel_exe.addAssemblyFile(b.path("arch/riscv64/k1/boot.S"));
    kernel_exe.addAssemblyFile(b.path("arch/riscv64/k1/switch.S"));
    kernel_exe.setLinkerScript(b.path("arch/riscv64/k1/kernel.ld"));
    kernel_exe.root_module.addImport("protocols", protocols_module);
    kernel_exe.want_lto = true;

    const install_kernel = b.addInstallArtifact(kernel_exe, .{});
    const kernel_step = b.step("kernel", "Build the Clarigggz RISC-V K1 Kernel");
    kernel_step.dependOn(&install_kernel.step);

    // --- x86_64 Simulator ---
    const simulator_exe = b.addExecutable(.{
        .name = "clarigggz-simulator",
        .root_source_file = b.path("simulator/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    simulator_exe.root_module.addImport("protocols", protocols_module);
    
    const install_simulator = b.addInstallArtifact(simulator_exe, .{});
    const simulator_step = b.step("simulator", "Build the Clarigggz Simulator (x86_64)");
    simulator_step.dependOn(&install_simulator.step);

    const run_simulator = b.addRunArtifact(simulator_exe);
    const run_step = b.step("simulate", "Run the Clarigggz OS Simulator");
    run_step.dependOn(&run_simulator.step);

    // --- Unit Tests ---
    const tests = b.addTest(.{
        .root_source_file = b.path("core/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.root_module.addImport("protocols", protocols_module);

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run all Clarigggz unit tests");
    test_step.dependOn(&run_tests.step);
}
