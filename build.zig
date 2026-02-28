const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --- Clarigggz Microkernel (core/) ---
    const kernel_exe = b.addExecutable(.{
        .name = "clarigggz-kernel",
        .root_source_file = b.path("core/main.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .riscv64,
            .os_tag = .freestanding,
            .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv64 }, // TODO: Refine for K1/RVV 1.0
        }),
        .optimize = optimize,
    });
    b.installArtifact(kernel_exe);

    // --- x86_64 Simulator (simulator/) ---
    const simulator_exe = b.addExecutable(.{
        .name = "clarigggz-simulator",
        .root_source_file = b.path("simulator/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(simulator_exe);

    const run_sim = b.addRunArtifact(simulator_exe);
    const sim_step = b.step("simulate", "Run the Clarigggz OS Simulator");
    sim_step.dependOn(&run_sim.step);

    // --- Protocols & Components ---
    // These will be added as modules to both the kernel and the simulator.
    const protocols_module = b.addModule("protocols", .{
        .root_source_file = b.path("protocols/root.zig"),
    });

    kernel_exe.root_module.addImport("protocols", protocols_module);
    simulator_exe.root_module.addImport("protocols", protocols_module);
}
