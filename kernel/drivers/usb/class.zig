//! This file provides the implementation of USB class drivers.

const std = @import("std");
const Allocator = std.mem.Allocator;
const UsbDevice = @import("device.zig").UsbDevice;
const descs = @import("descriptor.zig");
const ClassDriver = @import("class/driver.zig").ClassDriver;
const DriverError = @import("class/driver.zig").ClassDriverError;

pub const mouse = @import("class/mouse.zig");

const ClassError = error{
    UnsupportedClass,
    AllocationFailed,
    InvalidPhase,
};

/// Get a new class driver.
/// TODO: change return type for other class drivers.
pub fn newClassDriver(
    dev: *UsbDevice,
    if_desc: descs.InterfaceDescriptor,
    allocator: Allocator,
) ClassError!ClassDriver {
    if (if_desc.interface_class == 0x3 and if_desc.interface_subclass == 0x1) { // HID boot
        if (if_desc.interface_protocol == 0x2) {
            return mouse.MouseDriver.new(
                dev,
                if_desc.interface_number,
                allocator,
            ) catch |err| switch (err) {
                DriverError.AllocationFailed => ClassError.AllocationFailed,
                DriverError.InvalidPhase => ClassError.InvalidPhase,
            };
        }
    }

    return ClassError.UnsupportedClass;
}
