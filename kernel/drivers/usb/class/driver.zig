//! Base struct of USB class drivers.

const std = @import("std");
const zakuro = @import("zakuro");
const UsbDevice = zakuro.drivers.usb.device.UsbDevice;
const EndpoinInfo = zakuro.drivers.usb.endpoint.EndpointInfo;

pub const ClassDriverError = error{
    /// Failed to allocater memory.
    AllocationFailed,
};

pub const ClassDriver = @This();
pub const Self = ClassDriver;

ptr: *anyopaque,
vtable: *const VTable,

/// Index of the interface.
if_index: u8,
/// USB device.
device: *UsbDevice,
/// Endpoint ID of the IN direction.
ep_intr_in: EndpoinInfo = undefined,
/// Endpoint ID of the OUT direction.
ep_intr_out: EndpoinInfo = undefined,

pub const VTable = struct {};

/// Set the endpoint ID of the class driver.
pub fn setEndpoint(self: *Self, ep_config: EndpoinInfo) void {
    if (ep_config.ep_type == .Interrupt and ep_config.ep_id.direction == .In) {
        self.ep_intr_in = ep_config;
    } else if (ep_config.ep_type == .Interrupt and ep_config.ep_id.direction == .Out) {
        self.ep_intr_out = ep_config;
    }
}
