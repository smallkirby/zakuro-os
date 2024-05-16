//! This file provides the implementation of USB class drivers.

const std = @import("std");
const UsbDevice = @import("device.zig").UsbDevice;
const descs = @import("descriptor.zig");

pub const mouse = @import("class/mouse.zig");

const ClassError = error{
    UnsupportedClass,
};

/// Get a new class driver.
/// TODO: change return type for other class drivers.
pub fn newClassDriver(
    dev: *UsbDevice,
    if_desc: descs.InterfaceDescriptor,
) ClassError!mouse.MouseDriver {
    if (if_desc.interface_class == 0x3 and if_desc.interface_subclass == 0x1) { // HID boot
        if (if_desc.interface_protocol == 0x2) {
            return mouse.MouseDriver.new(dev, if_desc.interface_number);
        }
    }

    return ClassError.UnsupportedClass;
}
