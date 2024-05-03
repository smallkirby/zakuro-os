//! Kernel entry point.

const graphics = @import("graphics.zig");
const ser = @import("serial.zig");
const std = @import("std");
const klog = @import("log.zig");
const log = std.log.scoped(.main);
const console = @import("console.zig");

/// Override panic impl
pub const panic = @import("panic.zig").panic_fn;
/// Override log impl
pub const std_options = klog.default_log_options;

/// Kernel entry point called from the bootloader.
/// The bootloader is a UEFI app using MS x64 calling convention,
/// so we need to use the same calling convention here.
export fn kernel_main(fb_config: *graphics.FrameBufferConfig) callconv(.Win64) noreturn {
    const serial = ser.init();
    klog.init(serial);
    log.info("Booting Zakuro OS...", .{});

    const pixel_writer = graphics.PixelWriter.new(fb_config);

    var con = console.Console.new(pixel_writer, .{
        .red = 0xFF,
        .green = 0x00,
        .blue = 0x00,
    }, .{
        .red = 0x00,
        .green = 0x00,
        .blue = 0x00,
    });

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

    for (0..30) |i| {
        con.print("{d}: {s}\n", .{ i, "Hello from console...!" });
    }

    log.info("Reached end of kernel. Halting...", .{});
    while (true) {
        asm volatile ("hlt");
    }
}
