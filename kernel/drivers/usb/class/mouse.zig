//! This file provides a USB HID mouse class driver.

const std = @import("std");
const ClassDriver = @import("driver.zig").ClassDriver;
const Error = @import("driver.zig").ClassDriverError;
const Allocator = std.mem.Allocator;
const zakuro = @import("zakuro");
const UsbDevice = zakuro.drivers.usb.device.UsbDevice;

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
            .vtable = &.{},
        };
    }
};
