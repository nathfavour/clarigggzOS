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

    const core_module = b.addModule("core", .{
        .root_source_file = b.path("core/main.zig"),
    });
    core_module.addImport("protocols", protocols_module);

    // --- Clarigggz Microkernel (RISC-V K1) ---
    const kernel_exe = b.addExecutable(.{
        .name = "clarigggz-kernel",
        .root_module = b.createModule(.{
            .root_source_file = b.path("core/main.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .riscv64,
                .os_tag = .freestanding,
                .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv64 }, 
                .cpu_features_add = std.Target.riscv.featureSet(&.{.v}), // Enable RVV 1.0
            }),
            .optimize = optimize,
            .code_model = .medany,
        }),
    });
    kernel_exe.root_module.addAssemblyFile(b.path("arch/riscv64/k1/boot.S"));
    kernel_exe.root_module.addAssemblyFile(b.path("arch/riscv64/k1/switch.S"));
    kernel_exe.root_module.addAssemblyFile(b.path("arch/riscv64/k1/trap.S"));
    kernel_exe.setLinkerScript(b.path("arch/riscv64/k1/kernel.ld"));
    kernel_exe.root_module.addImport("protocols", protocols_module);
    kernel_exe.lto = .full;

    const install_kernel = b.addInstallArtifact(kernel_exe, .{});
    const kernel_step = b.step("kernel", "Build the Clarigggz RISC-V K1 Kernel");
    kernel_step.dependOn(&install_kernel.step);

    // --- Components (User-Space Adapters) ---
    const component_targets = [_]struct { name: []const u8, path: []const u8 }{
        .{ .name = "compositor", .path = "components/compositor/main.zig" },
        .{ .name = "tactile-id", .path = "components/tactile_id/main.zig" },
        .{ .name = "neural-engine", .path = "components/neural/main.zig" },
    };

    const components_step = b.step("components", "Build all user-space adapters");

    for (component_targets) |target_info| {
        const comp_exe = b.addExecutable(.{
            .name = b.fmt("clarigggz-{s}", .{target_info.name}),
            .root_module = b.createModule(.{
                .root_source_file = b.path(target_info.path),
                .target = b.resolveTargetQuery(.{
                    .cpu_arch = .riscv64,
                    .os_tag = .freestanding, // Simplified: will be Clarigggz OS tag in future
                    .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv64 },
                    .cpu_features_add = std.Target.riscv.featureSet(&.{.v}),
                }),
                .optimize = optimize,
            }),
        });
        comp_exe.root_module.addImport("protocols", protocols_module);
        const install_comp = b.addInstallArtifact(comp_exe, .{});
        components_step.dependOn(&install_comp.step);
    }

    // --- x86_64 Simulator ---
    const simulator_exe = b.addExecutable(.{
        .name = "clarigggz-simulator",
        .root_module = b.createModule(.{
            .root_source_file = b.path("simulator/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    simulator_exe.root_module.addImport("protocols", protocols_module);
    simulator_exe.root_module.addImport("core", core_module);
    
    const install_simulator = b.addInstallArtifact(simulator_exe, .{});
    const simulator_step = b.step("simulator", "Build the Clarigggz Simulator (x86_64)");
    simulator_step.dependOn(&install_simulator.step);

    const run_simulator = b.addRunArtifact(simulator_exe);
    const run_step = b.step("simulate", "Run the Clarigggz OS Simulator");
    run_step.dependOn(&run_simulator.step);

    // --- Unit Tests ---
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("core/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    tests.root_module.addImport("protocols", protocols_module);

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run all Clarigggz unit tests");
    test_step.dependOn(&run_tests.step);

    // --- ISO Build Step (Unified BSD System Image Packaging) ---
    const iso_step = b.step("iso", "Package Clarigggz OS into a bootable ISO image");
    
    const kernel_path = b.getInstallPath(.bin, "clarigggz-kernel");
    const iso_root_path = b.getInstallPath(.prefix, "iso_root");
    const boot_dir_path = b.getInstallPath(.prefix, "iso_root/boot");
    const grub_dir_path = b.getInstallPath(.prefix, "iso_root/boot/grub");
    const iso_out_path = b.getInstallPath(.prefix, "clarigggz.iso");

    const mkdir_cmd = b.addSystemCommand(&.{ "mkdir", "-p", grub_dir_path });
    const cp_kernel = b.addSystemCommand(&.{ "cp", kernel_path, boot_dir_path });
    cp_kernel.step.dependOn(&install_kernel.step);
    cp_kernel.step.dependOn(&mkdir_cmd.step);

    const grub_cfg_content = 
        \\menuentry "Clarigggz OS (Agent Sovereign)" {
        \\    multiboot /boot/clarigggz-kernel
        \\    boot
        \\}
    ;
    const write_grub = b.addSystemCommand(&.{ "sh", "-c", b.fmt("echo '{s}' > {s}/grub.cfg", .{grub_cfg_content, grub_dir_path}) });
    write_grub.step.dependOn(&cp_kernel.step);

    const mkrescue = b.addSystemCommand(&.{ "grub-mkrescue", "-o", iso_out_path, iso_root_path });
    mkrescue.step.dependOn(&write_grub.step);

    iso_step.dependOn(&mkrescue.step);
}
