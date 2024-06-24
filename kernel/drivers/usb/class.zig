//! This file provides the implementation of USB class drivers.

const std = @import("std");
const Allocator = std.mem.Allocator;
const UsbDevice = @import("device.zig").UsbDevice;
const descs = @import("descriptor.zig");
const ClassDriver = @import("class/driver.zig").ClassDriver;
const DriverError = @import("class/driver.zig").ClassDriverError;

pub const mouse = @import("class/mouse.zig");
pub const keyboard = @import("class/keyboard.zig");

pub const ClassError = error{
    UnsupportedClass,
    AllocationFailed,
    InvalidPhase,
    Unknown,
};

/// Get a new class driver.
pub fn newClassDriver(
    dev: *UsbDevice,
    if_desc: descs.InterfaceDescriptor,
    allocator: Allocator,
) ClassError!ClassDriver {
    if (if_desc.interface_class == 0x3 and if_desc.interface_subclass == 0x1) { // HID boot
        if (mouse.isMe(if_desc)) {
            return mouse.MouseDriver.new(
                dev,
                if_desc.interface_number,
                allocator,
            ) catch |err| parseError(err);
        } else if (keyboard.isMe(if_desc)) {
            return keyboard.KeyboardDriver.new(
                dev,
                if_desc.interface_number,
                allocator,
            ) catch |err| parseError(err);
        }
    }

    return ClassError.UnsupportedClass;
}

fn parseError(err: anytype) ClassError {
    return switch (err) {
        DriverError.AllocationFailed => ClassError.AllocationFailed,
        DriverError.InvalidPhase => ClassError.InvalidPhase,
        else => ClassError.Unknown,
    };
}
