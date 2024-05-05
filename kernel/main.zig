//! Kernel entry point.

const std = @import("std");
const zakuro = @import("zakuro");
const log = std.log.scoped(.main);
const console = zakuro.console;
const klog = zakuro.log;
const ser = zakuro.serial;
const graphics = zakuro.graphics;
const color = zakuro.color;
const pci = zakuro.pci;

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
    var con = console.Console.new(pixel_writer, color.GBFg, color.GBBg);

    // Clear the screen
    for (0..fb_config.horizontal_resolution) |x| {
        for (0..fb_config.vertical_resolution) |y| {
            pixel_writer.writePixel(@truncate(x), @truncate(y), color.LightPurple);
        }
    }
    // Draw a dock
    pixel_writer.fillRectangle(
        .{ .x = fb_config.horizontal_resolution - 0x30, .y = 0 },
        .{ .x = 0x30, .y = fb_config.vertical_resolution },
        color.DarkPurple,
    );
    // Draw hot button (mock)
    for (0..3) |x| {
        for (0..3) |y| {
            pixel_writer.fillRectangle(
                .{
                    .x = fb_config.horizontal_resolution - 0x20 + @as(u32, @truncate(x * 6)),
                    .y = fb_config.vertical_resolution - 0x20 + @as(u32, @truncate(y * 6)),
                },
                .{ .x = 3, .y = 3 },
                color.White,
            );
        }
    }

    for (0..30) |i| {
        con.print("{d}: {s}\n", .{ i, "Hello from console...!" });
    }

    pixel_writer.drawMouse(.{ .x = 100, .y = 200 });

    // Register PCI devices.
    pci.registerAllDevices();

    log.info("Reached end of kernel. Halting...", .{});
    while (true) {
        asm volatile ("hlt");
    }
}
