//! This file provides a USB HID mouse class driver.

const std = @import("std");
const ClassDriver = @import("driver.zig").ClassDriver;
const Error = @import("driver.zig").ClassDriverError;
const Allocator = std.mem.Allocator;
const zakuro = @import("zakuro");
const UsbDevice = zakuro.drivers.usb.device.UsbDevice;
const log = std.log.scoped(.mouse);

/// Observer for the mouse movements.
pub var mouse_observer: ?*const MouseObserver = null;

/// USB HID mouse class driver.
pub const MouseDriver = struct {
    const Self = @This();

    /// Instantiate the mouse driver.
    pub fn new(dev: *UsbDevice, if_index: u8, allocator: Allocator) Error!ClassDriver {
        const mouse = allocator.create(Self) catch return Error.AllocationFailed;
        mouse.* = Self{};

        return ClassDriver{
            .ptr = mouse,
            .device = dev,
            .if_index = if_index,
            .in_packed_size = 3,
            .vtable = &.{
                .onDataReceived = Self.onDataReceived,
            },
        };
    }

    fn onDataReceived(ctx: *anyopaque, buf: []u8) void {
        _ = ctx;

        const btn: u8 = buf[0];
        const displacement_x: i8 = @bitCast(buf[1]);
        const displacement_y: i8 = @bitCast(buf[2]);
        if (mouse_observer) |observer| {
            observer.onMove(btn, displacement_x, displacement_y);
        }
    }
};

/// Observer for the mouse driver.
/// The observer can be notified when the mouse moves.
pub const MouseObserver = struct {
    /// Instance of the observer.
    ptr: *anyopaque,
    /// vtable for the observer.
    vtable: VTable,

    const Self = @This();
    const VTable = struct {
        /// Called when the mouse moves.
        onMove: *const fn (*anyopaque, u8, i8, i8) void,
    };

    pub fn onMove(self: *const Self, btn: u8, displacement_x: i8, displacement_y: i8) void {
        self.vtable.onMove(self.ptr, btn, displacement_x, displacement_y);
    }
};
