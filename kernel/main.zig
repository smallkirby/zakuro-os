//! Kernel entry point.

const std = @import("std");
const zakuro = @import("zakuro");
const log = std.log.scoped(.main);
const console = zakuro.console;
const klog = zakuro.log;
const ser = zakuro.serial;
const graphics = zakuro.gfx;
const color = zakuro.color;
const pci = zakuro.pci;
const drivers = zakuro.drivers;
const mouse = zakuro.mouse;
const arch = zakuro.arch;
const intr = zakuro.arch.intr;

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
    log.info("BSP LAPIC ID: {d}", .{arch.getBspLapicId()});

    // Initialize IDT
    intr.init();
    log.info("Initialized IDT.", .{});

    const pixel_writer = graphics.PixelWriter.new(fb_config);
    var con = console.Console.new(pixel_writer, color.GBFg, color.GBBg);

    // Clear the screen
    for (0..fb_config.horizontal_resolution) |x| {
        for (0..fb_config.vertical_resolution) |y| {
            pixel_writer.writePixel(
                @bitCast(@as(u32, @truncate(x))),
                @bitCast(@as(u32, @truncate(y))),
                color.LightPurple,
            );
        }
    }
    // Draw a dock
    pixel_writer.fillRectangle(
        .{ .x = @intCast(fb_config.horizontal_resolution - 0x30), .y = 0 },
        .{ .x = 0x30, .y = fb_config.vertical_resolution },
        color.DarkPurple,
    );
    // Draw hot button (mock)
    for (0..3) |x| {
        for (0..3) |y| {
            pixel_writer.fillRectangle(
                .{
                    .x = @as(i32, @intCast(fb_config.horizontal_resolution)) - 0x20 + @as(i32, @intCast(x * 6)),
                    .y = @as(i32, @intCast(fb_config.vertical_resolution)) - 0x20 + @as(i32, @intCast(y * 6)),
                },
                .{ .x = 3, .y = 3 },
                color.White,
            );
        }
    }

    for (0..30) |i| {
        con.print("{d}: {s}\n", .{ i, "Hello from console...!" });
    }

    var cursor = mouse.MouseCursor{
        .ecolor = color.LightPurple,
        .pos = .{ .x = 100, .y = 100 },
        .writer = &pixel_writer,
        .screen_size = .{ .x = fb_config.horizontal_resolution, .y = fb_config.vertical_resolution },
    };
    cursor.drawMouse();

    // Register PCI devices.
    pci.registerAllDevices() catch |err| switch (err) {
        error.ListFull => {
            @panic("List of PCI devices if full. Can't register more devices.");
        },
    };
    for (0..pci.num_devices) |i| {
        if (pci.devices[i]) |info| {
            log.info("Found PCI device: {X:0>2}:{X:0>2}:{X:0>1} vendor={X:0>2} class={X:0>2}:{X:0>2}:{X:0>2}", .{
                info.device.bus,
                info.device.device,
                info.function,
                info.vendor_id,
                info.base_class,
                info.subclass,
                info.prog_if,
            });
        } else {
            @panic("Number of registered devices and its content mismatch.");
        }
    }

    // Find a xHC controller.
    var xhc_maybe: ?pci.DeviceInfo = null;
    for (0..pci.num_devices) |i| {
        if (pci.devices[i]) |info| {
            if (info.base_class == @intFromEnum(pci.ClassCodes.SerialBusController) and info.subclass == 0x03 and info.prog_if == 0x30) {
                xhc_maybe = info;
                // We assume that Intel's xHC controller is the main one.
                if (info.vendor_id == @intFromEnum(pci.KnownVendors.Intel)) {
                    break;
                }
            }
        }
    }
    const xhc_dev = xhc_maybe orelse @panic("xHC controller not found.");
    const bar0 = xhc_dev.device.readBar(xhc_dev.function, 0);
    const bar1 = xhc_dev.device.readBar(xhc_dev.function, 1);
    const xhc_mmio_base = (@as(u64, bar1) << 32) | @as(u64, bar0 & ~@as(u32, 0b1111));
    log.info("xHC MMIO base: 0x{X}", .{xhc_mmio_base});

    // Initialize xHC controller.
    var xhc = drivers.usb.xhc.Controller.new(xhc_mmio_base);
    xhc.init() catch |err| {
        log.err("Failed to initialize xHC controller: {?}", .{err});
        unreachable;
    };
    xhc.run();
    log.info("Started xHC controller.", .{});

    // Find available devices
    const max_ports = xhc.capability_regs.hcs_params1.read().maxports;
    for (1..max_ports) |i| {
        const port = xhc.getPortAt(i);
        if (port.isConnected()) {
            xhc.resetPort(port) catch |err| {
                log.err("Failed to reset port {d}: {?}", .{ i, err });
                continue;
            };
            log.info("Reset of port {d} completed.", .{i});
        }
    }

    const mouse_observer = cursor.observer();
    zakuro.drivers.usb.cls_mouse.mouse_observer = &mouse_observer;
    while (true) {
        xhc.processEvent() catch |err| {
            log.err("Failed to process event: {?}", .{err});
            @panic("Aborting...");
        };
    }

    // EOL
    log.info("Reached end of kernel. Halting...", .{});
    while (true) {
        asm volatile ("hlt");
    }
}
