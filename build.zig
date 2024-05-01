const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependency
    const chameleon = b.dependency("chameleon", .{});
    const clap = b.dependency("clap", .{});
    const plog = b.addModule("plog", .{
        .root_source_file = b.path("tools/mod/plog.zig"),
        .target = target,
        .optimize = optimize,
    });
    plog.addImport("chameleon", chameleon.module("chameleon"));

    // A tool to check if submodules are properly initialized.
    var run_ensure_submodule_step: *std.Build.Step = undefined;
    {
        const ensure_submodule = b.addExecutable(.{
            .name = "ensure_submodule",
            .root_source_file = b.path("tools/ensure_submodule.zig"),
            .target = target,
            .optimize = optimize,
        });
        ensure_submodule.root_module.addImport("plog", plog);

        const ensure_submodule_artifact = b.addRunArtifact(ensure_submodule);
        ensure_submodule_artifact.step.dependOn(&ensure_submodule.step);
        run_ensure_submodule_step = b.step("ensure_submodule", "Ensure submodule is up-to-date");
        run_ensure_submodule_step.dependOn(&ensure_submodule_artifact.step);
        b.getInstallStep().dependOn(run_ensure_submodule_step);
    }

    // A tool to generate a font binary and embed it into the kernel.
    var makefont_output: std.Build.LazyPath = undefined;
    {
        const makefont = b.addExecutable(.{
            .name = "makefont",
            .root_source_file = b.path("tools/fonts/makefont.zig"),
            .target = target,
            .optimize = optimize,
        });
        makefont.root_module.addImport("clap", clap.module("clap"));
        makefont.root_module.addImport("plog", plog);

        const makefont_artifact = b.addRunArtifact(makefont);
        makefont_artifact.addArg("--input");
        makefont_artifact.addFileArg(.{ .path = "./tools/fonts/half.txt" });
        makefont_artifact.addArg("--output");
        makefont_output = makefont_artifact.addOutputFileArg("font.o");
        makefont_artifact.step.dependOn(&makefont.step);

        const run_makefont_step = b.step("makefont", "Generate a font binary");
        run_makefont_step.dependOn(&makefont_artifact.step);
        const f = b.addInstallFileWithDir(makefont_output, .prefix, "font.o");
        b.getInstallStep().dependOn(&f.step);
    }

    // A tool to build EFI using EDK2.
    {
        const build_efi = b.addExecutable(.{
            .name = "build_efi",
            .root_source_file = b.path("tools/build_efi.zig"),
            .target = target,
            .optimize = optimize,
        });
        build_efi.root_module.addImport("plog", plog);

        const build_efi_artifact = b.addRunArtifact(build_efi);
        build_efi_artifact.step.dependOn(&build_efi.step);
        const run_build_efi_step = b.step("build_efi", "Build EFI using EDK2");
        run_build_efi_step.dependOn(&build_efi_artifact.step);
        b.getInstallStep().dependOn(run_build_efi_step);
        build_efi_artifact.step.dependOn(run_ensure_submodule_step);
    }

    // Declare a run step to run C linter.
    {
        const run_clint_cmd = b.addSystemCommand(&.{
            "tools/lint_c",
        });
        const run_clint_step = b.step("lint_c", "Run C linter");
        run_clint_step.dependOn(&run_clint_cmd.step);
    }

    // Main binary
    var kernel: *std.Build.Step.Compile = undefined;
    {
        kernel = b.addExecutable(.{
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
        kernel.root_module.red_zone = false;
        kernel.image_base = 0x10_0000;
        kernel.link_z_relro = false;
        kernel.entry = .{ .symbol_name = "kernel_main" };
        kernel.addObjectFile(makefont_output);

        b.installArtifact(kernel);
    }

    // Declare a run step to run QEMU.
    {
        const run_qemu_cmd = b.addSystemCommand(&.{
            "tools/run_qemu",
            "disk.img",
            "Loader.efi",
            std.fs.path.join(b.allocator, &.{
                b.install_path,
                "bin",
                kernel.out_filename,
            }) catch {
                @panic("Failed to join path of 'run_qemu_cmd()'");
            },
        });
        run_qemu_cmd.step.dependOn(b.getInstallStep());

        const run_step = b.step("run", "Run the kernel on QEMU");
        run_step.dependOn(&run_qemu_cmd.step);
    }

    // Declare a test step.
    {
        const exe_unit_tests = b.addTest(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&run_exe_unit_tests.step);
    }
}
