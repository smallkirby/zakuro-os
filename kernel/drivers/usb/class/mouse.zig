//! This file provides a USB HID mouse class driver.

const zakuro = @import("zakuro");
const UsbDevice = zakuro.drivers.usb.device.UsbDevice;

/// USB HID mouse class driver.
pub const MouseDriver = struct {
    /// USB device.
    device: *UsbDevice,
    /// Index of the interface.
    if_index: u8,

    const Self = @This();

    /// Instantiate the mouse driver.
    pub fn new(dev: *UsbDevice, if_index: u8) Self {
        return Self{
            .device = dev,
            .if_index = if_index,
        };
    }
};
