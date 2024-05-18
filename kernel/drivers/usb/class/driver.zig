//! Base struct of USB class drivers.

const std = @import("std");
const zakuro = @import("zakuro");
const UsbDevice = zakuro.drivers.usb.device.UsbDevice;
const EndpoinInfo = zakuro.drivers.usb.endpoint.EndpointInfo;
const default_control_pipe_id = zakuro.drivers.usb.endpoint.default_control_pipe_id;
const SetupData = zakuro.drivers.usb.setupdata.SetupData;
const log = std.log.scoped(.uclass);

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

/// Enable boot protocol.
pub fn onEndpointConfigured(self: *Self) !void {
    const sud = SetupData{
        .bm_request_type = .{
            .dtd = .Out,
            .type = .Class,
            .recipient = .Interface,
        },
        .b_request = .SetInterface,
        .w_value = 0, // boot protocol
        .w_index = self.if_index,
        .w_length = 0,
    };

    try self.device.controlOut(default_control_pipe_id, sud, null, self);
}
