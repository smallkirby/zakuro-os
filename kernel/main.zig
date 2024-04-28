//! Kernel entry point.

const fb = @import("frame_buffer.zig");

/// Kernel entry point called from the bootloader.
/// The bootloader is a UEFI app using MS x64 calling convention,
/// so we need to use the same calling convention here.
export fn kernel_main(fb_config: *fb.FrameBufferConfig) callconv(.Win64) noreturn {
    for (0..fb_config.horizontal_resolution) |x| {
        for (0..fb_config.vertical_resolution) |y| {
            write_pixel(fb_config, @truncate(x), @truncate(y), .{
                .red = 0xFF,
                .green = 0xFF,
                .blue = 0xFF,
            });
        }
    }

    for (0..200) |x| {
        for (0..200) |y| {
            write_pixel(
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

/// Draw a pixel at the given position of the framebuffer with the given color.
fn write_pixel(config: *fb.FrameBufferConfig, x: u32, y: u32, color: fb.PixelColor) void {
    const pixel_position = config.pixels_per_scan_line * y + x;
    switch (config.pixel_format) {
        .PixelRGBResv8BitPerColor => {
            const p: [*]u8 = @ptrCast(&config.frame_buffer[4 * pixel_position]);
            p[0] = color.red;
            p[1] = color.green;
            p[2] = color.blue;
        },
        .PixelBGRResv8BitPerColor => {
            const p: [*]u8 = @ptrCast(&config.frame_buffer[4 * pixel_position]);
            p[0] = color.blue;
            p[1] = color.green;
            p[2] = color.red;
        },
    }
}
