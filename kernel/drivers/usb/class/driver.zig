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
    /// Invalid phase
    InvalidPhase,
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
/// TODO: doc
in_packed_size: u32,

/// Initialization phase
phase: Phase = .NotInitialized,
/// General purpose buffer for this driver.
/// Any alignment is allowed.
buffer: [buffer_size]u8 = [_]u8{0} ** buffer_size,
const buffer_size = 1024;

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

    self.phase = .Phase1;
    try self.device.controlOut(default_control_pipe_id, sud, null, self);
}

/// TODO: doc
pub fn onControlComplete(self: *Self) !void {
    if (self.phase != .Phase1) {
        return ClassDriverError.InvalidPhase;
    }

    self.phase = .Phase2;
    try self.device.interruptIn(self.ep_intr_in.ep_id, self.buffer[0..self.in_packed_size]);
}

const Phase = enum {
    NotInitialized,
    Phase1,
    Phase2,
    Phase3,
};
