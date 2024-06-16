//! Kernel entry point.

const std = @import("std");
const log = std.log.scoped(.main);

const zakuro = @import("zakuro");
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
const FixedSizeQueue = zakuro.lib.queue.FixedSizeQueue;
const mm = zakuro.mm;
const MemoryMap = mm.uefi.MemoryMap;
const BitmapPageAllocator = mm.BitmapPageAllocator;
const SlubAllocator = mm.SlubAllocator;
const gfx = zakuro.gfx;

/// Override panic impl
pub const panic = @import("panic.zig").panic_fn;
/// Override log impl
pub const std_options = klog.default_log_options;

const kstack_size = arch.page_size * 0x50;
/// Kernel stack
var kstack: [kstack_size]u8 align(16) = [_]u8{0} ** kstack_size;

/// Buffer for BitmapPageAllocator.
/// TODO: allocate memory dynamically
var bpa_buf: [@sizeOf(BitmapPageAllocator)]u8 align(4096) = [_]u8{0} ** @sizeOf(BitmapPageAllocator);

/// xHC controller.
/// TODO: Move this to a proper place.
var xhc: drivers.usb.xhc.Controller = undefined;
/// Interrupt queue.
/// TODO: Move this to a proper place.
var intr_queue: FixedSizeQueue(IntrMessage) = undefined;

/// Instance of a console.
var con: console.Console = undefined;

/// Interrupt message.
/// The message is queued in the interrupt handler and processed in the main loop.
/// TODO: Move this to a proper place.
const IntrMessage = struct {
    /// Type of the message.
    typ: enum {
        /// Mouse event.
        Mouse,
    },
};

/// Kernel entry point called from the bootloader.
/// This function switches to the kernel stack and calls `kernel_main`.
export fn kernel_entry() callconv(.Naked) noreturn {
    asm volatile (
        \\movq %[new_stack], %%rsp
        \\call kernel_main
        :
        : [new_stack] "r" (@intFromPtr(&kstack) + kstack_size),
    );
}

/// Kernel Zig entry point called from UEFI via kernel_entry.
/// The bootloader is a UEFI app using MS x64 calling convention,
/// so we need to use the same calling convention here.
export fn kernel_main(
    fb_config: *graphics.FrameBufferConfig,
    memory_map: *MemoryMap,
) callconv(.Win64) noreturn {
    // This function runs on the new kernel stack,
    // but the arguments are still placed in the old stack.
    // Therefore, we copy the arguments in the new stack and pass their pointers to `main`.
    var new_fb_config = fb_config.*;
    var new_memory_map = memory_map.*;

    main(&new_fb_config, &new_memory_map) catch |err| switch (err) {
        else => {
            log.err("Uncaught kernel error: {?}", .{err});
            @panic("Aborting...");
        },
    };

    unreachable;
}

fn main(
    fb_config: *graphics.FrameBufferConfig,
    memory_map: *MemoryMap,
) !void {
    const serial = ser.init();
    klog.init(serial);

    log.info("Booting Zakuro OS...", .{});
    log.info("BSP LAPIC ID: {d}", .{arch.getBspLapicId()});

    // Initialize IDT
    intr.init();
    log.info("Initialized IDT.", .{});

    // Initialize GDT
    arch.gdt.init();
    log.info("Initialized GDT.", .{});

    // Initialize page allocator
    var bpa = BitmapPageAllocator.init(memory_map, &bpa_buf);
    const page_allocator = bpa.allocator();
    var slub_allocator = try SlubAllocator.init(bpa);
    const gpa = slub_allocator.allocator();

    // Initialize paging.
    try arch.page.initIdentityMapping(page_allocator);

    // Initialize interrupt queue
    intr_queue = try FixedSizeQueue(IntrMessage).init(16, gpa);

    // Initialize a pixel writer
    const pixel_writer = graphics.PixelWriter.new(fb_config);
    gfx.layer.initialize(pixel_writer, fb_config.*, gpa);

    // Initialize graphic layers
    var layers = gfx.layer.getLayers();
    const bgwindow = try layers.spawnWindow(
        fb_config.horizontal_resolution,
        fb_config.vertical_resolution,
    );

    // Draw desktop and dock bar.
    gfx.lib.drawDesktop(bgwindow);
    gfx.lib.drawDock(bgwindow);

    // Initialize graphic console
    con = console.Console.new(
        bgwindow,
        color.GBFg,
        color.GBBg,
    );
    klog.setConsole(&con);

    // Initialize graphic mouse cursor
    const mouse_window = try layers.spawnWindow(
        mouse.mouse_cursor_width,
        mouse.mouse_cursor_height,
    );
    mouse_window.moveOrigin(.{ .x = 0x100, .y = 0x100 });
    mouse_window.transparent_color = mouse.mouse_transparent_color;
    var cursor = mouse.MouseCursor{
        .ecolor = color.LightPurple,
        .window = mouse_window,
    };
    cursor.drawMouse();

    // Flush graphic layers to render.
    layers.flush();

    // Register PCI devices.
    try pci.registerAllDevices();
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
    intr.registerHandler(mouse.intr_vector, &mouseHandler);
    try xhc_dev.configureMsi(
        .{ .dest_id = arch.getBspLapicId() },
        .{ .vector = mouse.intr_vector, .assert = true },
        0,
    );

    const bar0 = xhc_dev.device.readBar(xhc_dev.function, 0);
    const bar1 = xhc_dev.device.readBar(xhc_dev.function, 1);
    const xhc_mmio_base = (@as(u64, bar1) << 32) | @as(u64, bar0 & ~@as(u32, 0b1111));
    log.info("xHC MMIO base: 0x{X}", .{xhc_mmio_base});

    // TODO: identity map for MMIO base in case it exceeds 16GiB.
    try arch.page.mapIdentity(xhc_mmio_base, gpa);

    // Initialize xHC controller.
    xhc = drivers.usb.xhc.Controller.new(xhc_mmio_base, gpa);
    try xhc.init();
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

    // TODO: We cannot move a mouse cursor until here.
    //   Users may think the system is frozen while the console output is still working.
    const mouse_observer = cursor.observer();
    zakuro.drivers.usb.cls_mouse.mouse_observer = &mouse_observer;

    // Loop to process interrupt messages
    while (true) {
        // Check if there is any interrupt message
        arch.disableIntr();
        {
            if (intr_queue.len == 0) {
                arch.enableIntr();
                arch.halt();
                continue;
            }
        }
        arch.enableIntr();

        // Process the message
        if (intr_queue.pop()) |msg| {
            switch (msg.typ) {
                .Mouse => handleMouseMessage(),
            }
        }
    }

    // EOL
    log.info("Reached end of kernel. Halting...", .{});
    while (true) {
        arch.halt();
    }
}

// TODO: Move this to a proper place.
fn mouseHandler(_: *intr.Context) void {
    intr_queue.push(.{ .typ = .Mouse }) catch |err| {
        log.err("Failed to push mouse event to the queue: {?}", .{err});
    };
    intr.notifyEoi();
}

// TODO: Move this to a proper place.
fn handleMouseMessage() void {
    while (xhc.hasEvent()) {
        xhc.processEvent() catch |err| {
            log.err("Failed to process xHC event: {?}", .{err});
        };
    }
}
