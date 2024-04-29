//! Kernel entry point.

const fb = @import("frame_buffer.zig");

/// Kernel entry point called from the bootloader.
/// The bootloader is a UEFI app using MS x64 calling convention,
/// so we need to use the same calling convention here.
export fn kernel_main(fb_config: *fb.FrameBufferConfig) callconv(.Win64) noreturn {
    for (0..fb_config.horizontal_resolution) |x| {
        for (0..fb_config.vertical_resolution) |y| {
            fb.write_pixel(fb_config, @truncate(x), @truncate(y), .{
                .red = 0xFF,
                .green = 0xFF,
                .blue = 0xFF,
            });
        }
    }

    for (0..200) |x| {
        for (0..200) |y| {
            fb.write_pixel(
                fb_config,
                @truncate(x + 100),
                @truncate(y + 100),
                .{
                    .red = 0x00,
                    .green = 0x00,
                    .blue = 0xFF,
                },
            );
        }
    }

    while (true) {
        asm volatile ("hlt");
    }
}
