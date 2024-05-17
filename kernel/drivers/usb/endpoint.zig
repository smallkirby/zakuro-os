//! This file defines the Endpoint of USB2/USB3 spec.

const descs = @import("descriptor.zig");

/// Endpoint ID for the default control pipe.
pub const default_control_pipe_id = EndpointId{ .number = 0, .direction = .In };

/// USB Endpoint.
pub const Endpoint = struct {
    /// Address of the endpoint
    addr: u32,

    const Self = @This();

    pub fn new(ep_num: u8, direction: EndpointDirection) Self {
        const id = EndpointId{ .number = ep_num, .direction = direction };
        return Self{
            .addr = id.addr(),
        };
    }
};

pub const EndpointId = struct {
    /// Endpoint number
    number: u8,
    /// Direction of endpoint
    direction: EndpointDirection,

    pub fn from(actual_addr: u32) EndpointId {
        return EndpointId{
            .number = @truncate(actual_addr >> 1),
            .direction = @enumFromInt(actual_addr & 1),
        };
    }

    pub fn addr(self: EndpointId) u32 {
        return (self.number << 1) + @intFromEnum(self.direction);
    }
};

/// Configuration information for an endpoint.
pub const EndpointInfo = struct {
    /// ID of the endpoint.
    ep_id: EndpointId,
    /// Type of the endpoint.
    ep_type: EndpointType,
    /// Maximum packet size of the endpoint.
    max_packet_size: u32,
    /// Polling interval of the endpoint.
    interval: u32,

    pub fn new(ep_desc: descs.EndpointDescriptor) EndpointInfo {
        return EndpointInfo{
            .ep_id = EndpointId{
                .number = ep_desc.endpoint_address,
                .direction = .In,
            },
            .ep_type = @enumFromInt(@intFromEnum(ep_desc.attributes.transfer_type)),
            .max_packet_size = ep_desc.max_packet_size,
            .interval = ep_desc.interval,
        };
    }
};

const EndpointDirection = enum(u1) {
    Out = 0,
    In = 1,
};

const EndpointType = enum(u3) {
    Control = 0,
    Isochronous = 1,
    Bulk = 2,
    Interrupt = 3,
};
