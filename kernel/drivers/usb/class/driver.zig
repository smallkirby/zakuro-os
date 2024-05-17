//! Base struct of USB class drivers.

const std = @import("std");
const zakuro = @import("zakuro");
const UsbDevice = zakuro.drivers.usb.device.UsbDevice;

pub const ClassDriverError = error{
    /// Failed to allocater memory.
    AllocationFailed,
};

pub const ClassDriver = @This();

ptr: *anyopaque,
vtable: *const VTable,

/// Index of the interface.
if_index: u8,
/// USB device.
device: *UsbDevice,

pub const VTable = struct {};
