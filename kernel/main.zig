//! TODO

/// Kernel entry point called from the bootloader.
/// The bootloader is a UEFI app using MS x64 calling convention,
/// so we need to use the same calling convention here.
export fn kernel_main(
    frame_buffer_base: [*]u8,
    frame_buffer_size: u64,
) callconv(.Win64) noreturn {
    for (0..frame_buffer_size) |i| {
        frame_buffer_base[i] = @as(u8, @truncate(i & 0xFF)) % 255;
    }

    while (true) {
        asm volatile ("hlt");
    }
}
