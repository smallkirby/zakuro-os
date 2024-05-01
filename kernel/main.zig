//! Kernel entry point.

const graphics = @import("graphics.zig");

/// Kernel entry point called from the bootloader.
/// The bootloader is a UEFI app using MS x64 calling convention,
/// so we need to use the same calling convention here.
export fn kernel_main(fb_config: *graphics.FrameBufferConfig) callconv(.Win64) noreturn {
    const pixel_writer = graphics.PixelWriter.new(fb_config);
    for (0..fb_config.horizontal_resolution) |x| {
        for (0..fb_config.vertical_resolution) |y| {
            pixel_writer.write_pixel(@truncate(x), @truncate(y), .{
                .red = 0xFF,
                .green = 0xFF,
                .blue = 0xFF,
            });
        }
    }

    for (0..200) |x| {
        for (0..200) |y| {
            pixel_writer.write_pixel(
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

    for ("Hello, Zakuro OS!", 0..) |c, i| {
        const x = 50 + @as(u32, @truncate(i * 8));
        try pixel_writer.write_ascii(x, 50, c, .{
            .red = 0xFF,
            .green = 0x00,
            .blue = 0x00,
        });
    }

    while (true) {
        asm volatile ("hlt");
    }
}
