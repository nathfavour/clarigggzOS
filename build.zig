const std = @import("std");

pub fn build(b: *std.Build) void {
    // --- Target Configuration ---
    const riscv_query = std.Target.Query{
        .cpu_arch = .riscv64,
        .os_tag = .freestanding,
        .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv64 },
    };
    const riscv_rvv_query = std.Target.Query{
        .cpu_arch = .riscv64,
        .os_tag = .freestanding,
        .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv64 },
        .cpu_features_add = std.Target.riscv.featureSet(&.{.v}),
    };
    const target = b.standardTargetOptions(.{
        .default_target = riscv_rvv_query,
    });
    const optimize = b.standardOptimizeOption(.{});
    const target_info = target.result;
    const kernel_riscv_target = b.resolveTargetQuery(riscv_query);
    const rvv_riscv_target = b.resolveTargetQuery(riscv_rvv_query);

    // Set the install prefix to 'bin/' as mandated by AGENTS.md
    b.install_path = "bin";

    // --- Hardware Platform Selection ---
    const hw_target = b.option(
        []const u8,
        "hardware",
        "Target hardware platform (qemu_virt or spacemit_k1)",
    ) orelse "qemu_virt";

    const tee_backend = b.option(
        []const u8,
        "tee_backend",
        "TEE backend: stub or keystone",
    ) orelse "stub";

    const options = b.addOptions();
    options.addOption([]const u8, "hardware", hw_target);
    options.addOption(bool, "kernel_adapter", false);
    options.addOption([]const u8, "tee_backend", tee_backend);
    const options_mod = options.createModule();

    const kernel_adapter_options = b.addOptions();
    kernel_adapter_options.addOption([]const u8, "hardware", hw_target);
    kernel_adapter_options.addOption(bool, "kernel_adapter", true);
    kernel_adapter_options.addOption([]const u8, "tee_backend", tee_backend);
    const kernel_adapter_options_mod = kernel_adapter_options.createModule();

    // --- Modules ---
    const protocols_module = b.addModule("protocols", .{
        .root_source_file = b.path("protocols/root.zig"),
    });

    const core_module = b.addModule("core", .{
        .root_source_file = b.path("core/main.zig"),
    });
    core_module.addImport("protocols", protocols_module);
    core_module.addOptions("config", options);

    // --- Clarigggz Microkernel ---
    const kernel_exe = b.addExecutable(.{
        .name = "clarigggz-kernel",
        .root_module = b.createModule(.{
            .root_source_file = b.path("core/main.zig"),
            .target = kernel_riscv_target,
            .optimize = optimize,
        }),
    });
    kernel_exe.root_module.addOptions("config", options);

    // Dynamically apply architecture-specific boot code and linker scripts
    switch (target_info.cpu.arch) {
        .riscv64 => {
            kernel_exe.root_module.addAssemblyFile(b.path("arch/riscv64/k1/boot.S"));
            kernel_exe.root_module.addAssemblyFile(b.path("arch/riscv64/k1/switch.S"));
            kernel_exe.root_module.addAssemblyFile(b.path("arch/riscv64/k1/trap.S"));
            kernel_exe.setLinkerScript(b.path("arch/riscv64/k1/kernel.ld"));
            kernel_exe.root_module.code_model = .medany;
        },
        .x86_64 => {
            kernel_exe.root_module.addAssemblyFile(b.path("arch/x86_64/boot.S"));
            kernel_exe.setLinkerScript(b.path("arch/x86_64/kernel.ld"));
        },
        else => {
            // Default generic fallback
        },
    }

    kernel_exe.root_module.addImport("protocols", protocols_module);

    const adapter_modules = [_]struct { name: []const u8, path: []const u8 }{
        .{ .name = "compositor_adapter", .path = "components/compositor/main.zig" },
        .{ .name = "neural_adapter", .path = "components/neural/main.zig" },
        .{ .name = "tactile_adapter", .path = "components/tactile_id/main.zig" },
        .{ .name = "agent_adapter", .path = "components/agent/main.zig" },
    };
    var adapter_mods: [adapter_modules.len]*std.Build.Module = undefined;
    for (adapter_modules, 0..) |am, i| {
        const adapter_target = if (std.mem.eql(u8, am.name, "neural_adapter"))
            rvv_riscv_target
        else
            kernel_riscv_target;
        const mod = b.createModule(.{
            .root_source_file = b.path(am.path),
            .target = adapter_target,
            .optimize = optimize,
        });
        mod.addImport("protocols", protocols_module);
        mod.addImport("config", kernel_adapter_options_mod);
        adapter_mods[i] = mod;
        kernel_exe.root_module.addImport(am.name, mod);
    }

    kernel_exe.lto = .none;

    const install_kernel = b.addInstallArtifact(kernel_exe, .{});
    const kernel_step = b.step("kernel", "Build the Clarigggz Microkernel");
    kernel_step.dependOn(&install_kernel.step);

    // --- Components (User-Space Adapters) ---
    const component_targets = [_]struct { name: []const u8, path: []const u8 }{
        .{ .name = "compositor", .path = "components/compositor/main.zig" },
        .{ .name = "tactile-id", .path = "components/tactile_id/main.zig" },
        .{ .name = "neural-engine", .path = "components/neural/main.zig" },
        .{ .name = "agent-runtime", .path = "components/agent/main.zig" },
    };

    const components_step = b.step("components", "Build all user-space adapters");

    for (component_targets) |target_info_item| {
        const component_target = if (std.mem.eql(u8, target_info_item.name, "neural-engine"))
            rvv_riscv_target
        else
            kernel_riscv_target;
        const comp_exe = b.addExecutable(.{
            .name = b.fmt("clarigggz-{s}", .{target_info_item.name}),
            .root_module = b.createModule(.{
                .root_source_file = b.path(target_info_item.path),
                .target = component_target,
                .optimize = optimize,
            }),
        });
        comp_exe.root_module.addImport("protocols", protocols_module);
        comp_exe.root_module.addImport("config", options_mod);
        const install_comp = b.addInstallArtifact(comp_exe, .{});
        components_step.dependOn(&install_comp.step);
    }

    // Copy adapter ELFs into core/blobs/ for optional ELF loading at boot
    const blobs_dir = "core/blobs";
    const mkdir_blobs = b.addSystemCommand(&.{ "mkdir", "-p", blobs_dir });
    const embed_step = b.step("embed-adapters", "Copy adapter ELFs to core/blobs for ELF loader");

    const blob_meta = [_]struct { file: []const u8, name: []const u8, priority: u8, uses_vectors: bool }{
        .{ .file = "compositor.elf", .name = "compositor", .priority = 5, .uses_vectors = false },
        .{ .file = "tactile-id.elf", .name = "tactile-id", .priority = 3, .uses_vectors = false },
        .{ .file = "neural-engine.elf", .name = "neural-engine", .priority = 8, .uses_vectors = true },
        .{ .file = "agent-runtime.elf", .name = "agent-runtime", .priority = 4, .uses_vectors = false },
    };

    var last_cp: ?*std.Build.Step = null;
    for (blob_meta) |meta| {
        const src = b.fmt("zig-out/bin/clarigggz-{s}", .{meta.name});
        const dst = b.fmt("core/blobs/{s}", .{meta.file});
        const cp = b.addSystemCommand(&.{ "cp", src, dst });
        cp.step.dependOn(components_step);
        cp.step.dependOn(&mkdir_blobs.step);
        embed_step.dependOn(&cp.step);
        last_cp = &cp.step;
    }

    const gen_embed = b.addSystemCommand(&.{
        "sh", "-c",
        b.fmt(
            \\cat > core/embedded_adapters.zig <<'EMBED_EOF'
            \\//! Embedded adapter ELF blobs (generated by `zig build embed-adapters`).
            \\pub const Blob = struct {{
            \\    name: []const u8,
            \\    priority: u8,
            \\    uses_vectors: bool,
            \\    data: []const u8,
            \\}};
            \\
            \\pub const blobs = [_]Blob{{
            \\    .{{ .name = "compositor", .priority = 5, .uses_vectors = false, .data = @embedFile("blobs/compositor.elf") }},
            \\    .{{ .name = "tactile-id", .priority = 3, .uses_vectors = false, .data = @embedFile("blobs/tactile-id.elf") }},
            \\    .{{ .name = "neural-engine", .priority = 8, .uses_vectors = true, .data = @embedFile("blobs/neural-engine.elf") }},
            \\    .{{ .name = "agent-runtime", .priority = 4, .uses_vectors = false, .data = @embedFile("blobs/agent-runtime.elf") }},
            \\}};
            \\EMBED_EOF
        , .{}),
    });
    gen_embed.step.dependOn(last_cp.?);
    embed_step.dependOn(&gen_embed.step);

    // Raw binary extraction for QEMU / bare-metal deployment
    const kernel_path = b.getInstallPath(.bin, "clarigggz-kernel");
    const bin_out_path = b.getInstallPath(.bin, "clarigggz.bin");
    const objcopy = b.addSystemCommand(&.{
        "llvm-objcopy",
        "-O",
        "binary",
        kernel_path,
        bin_out_path,
    });
    objcopy.step.dependOn(&install_kernel.step);
    const bin_step = b.step("bin", "Generate raw binary clarigggz.bin for QEMU");
    bin_step.dependOn(&objcopy.step);

    // QEMU smoke run for fast bring-up iteration.
    const qemu_run = b.addSystemCommand(&.{
        "sh",
        "-c",
        b.fmt(
            "timeout 12 qemu-system-riscv64 -M virt -cpu rv64,v=true -smp 1 -m 512M -bios default -kernel {s} -nographic -serial mon:stdio; rc=$?; if [ \"$rc\" -eq 124 ]; then exit 0; fi; exit \"$rc\"",
            .{bin_out_path},
        ),
    });
    qemu_run.step.dependOn(&objcopy.step);
    const qemu_step = b.step("qemu", "Run Clarigggz on QEMU virt (RVV enabled)");
    qemu_step.dependOn(&qemu_run.step);

    const compositor_module = b.addModule("compositor", .{
        .root_source_file = b.path("components/compositor/main.zig"),
    });
    compositor_module.addImport("protocols", protocols_module);

    const host_target = b.resolveTargetQuery(.{});

    // --- x86_64 Simulator ---
    const simulator_exe = b.addExecutable(.{
        .name = "clarigggz-simulator",
        .root_module = b.createModule(.{
            .root_source_file = b.path("simulator/main.zig"),
            .target = host_target,
            .optimize = optimize,
        }),
    });
    simulator_exe.root_module.addImport("protocols", protocols_module);
    simulator_exe.root_module.addImport("core", core_module);
    simulator_exe.root_module.addImport("compositor", compositor_module);

    
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
            .target = host_target,

            .optimize = optimize,
        }),
    });
    tests.root_module.addImport("protocols", protocols_module);
    tests.root_module.addOptions("config", options);

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run all Clarigggz unit tests");
    test_step.dependOn(&run_tests.step);

    // --- ISO Build Step (Unified BSD System Image Packaging) ---
    const iso_step = b.step("iso", "Package Clarigggz OS into a bootable ISO image");
    
    const iso_kernel_path = b.getInstallPath(.bin, "clarigggz-kernel");
    const iso_root_path = b.getInstallPath(.prefix, "iso_root");
    const boot_dir_path = b.getInstallPath(.prefix, "iso_root/boot");
    const grub_dir_path = b.getInstallPath(.prefix, "iso_root/boot/grub");
    const iso_out_path = b.getInstallPath(.prefix, "clarigggz.iso");

    const mkdir_cmd = b.addSystemCommand(&.{ "mkdir", "-p", grub_dir_path });
    const cp_kernel = b.addSystemCommand(&.{ "cp", iso_kernel_path, boot_dir_path });

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
