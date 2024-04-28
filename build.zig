const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main binary (TODO).
    const exe = b.addExecutable(.{
        .name = "kernel.elf",
        .root_source_file = b.path("kernel/main.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .x86_64,
            .os_tag = .freestanding,
            .ofmt = .elf,
        }),
        .optimize = .Debug,
        .linkage = .static,
    });
    exe.root_module.red_zone = false;
    exe.image_base = 0x10_0000;
    exe.link_z_relro = false;
    exe.entry = .{ .symbol_name = "kernel_main" };
    b.installArtifact(exe);

    // Dependency
    const chameleon = b.dependency("chameleon", .{});

    // Declare a tool to check for submodule updates and initialization.
    const ensure_submodule = b.addExecutable(.{
        .name = "ensure_submodule",
        .root_source_file = b.path("tools/ensure_submodule.zig"),
        .target = target,
        .optimize = optimize,
    });
    ensure_submodule.root_module.addImport("chameleon", chameleon.module("chameleon"));

    const ensure_submodule_cmd = b.addRunArtifact(ensure_submodule);
    ensure_submodule_cmd.step.dependOn(&ensure_submodule.step);
    const run_ensure_submodule_step = b.step("ensure_submodule", "Ensure submodule is up-to-date");
    run_ensure_submodule_step.dependOn(&ensure_submodule_cmd.step);
    exe.step.dependOn(run_ensure_submodule_step);

    // Declare a tool to build EFI using EDK2.
    const build_efi = b.addExecutable(.{
        .name = "build_efi",
        .root_source_file = b.path("tools/build_efi.zig"),
        .target = target,
        .optimize = optimize,
    });
    build_efi.root_module.addImport("chameleon", chameleon.module("chameleon"));

    const build_efi_cmd = b.addRunArtifact(build_efi);
    build_efi_cmd.step.dependOn(&build_efi.step);
    const run_build_efi_step = b.step("build_efi", "Build EFI using EDK2");
    run_build_efi_step.dependOn(&build_efi_cmd.step);
    exe.step.dependOn(run_build_efi_step);
    build_efi_cmd.step.dependOn(run_ensure_submodule_step);

    // Declare a run step to run QEMU.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const run_qemu_cmd = b.addSystemCommand(&.{
        "tools/run_qemu",
        "disk.img",
        "Loader.efi",
        std.fs.path.join(allocator, &.{
            b.install_path,
            "bin",
            exe.out_filename,
        }) catch {
            @panic("Failed to join path");
        },
    });
    run_qemu_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the kernel on QEMU");
    run_step.dependOn(&run_qemu_cmd.step);

    // Declare a run step to run C linter.
    const run_clint_cmd = b.addSystemCommand(&.{
        "tools/lint_c",
    });
    const run_clint_step = b.step("lint_c", "Run C linter");
    run_clint_step.dependOn(&run_clint_cmd.step);

    // Test step
    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
