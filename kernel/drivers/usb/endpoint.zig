//! This file defines the Endpoint of USB2/USB3 spec.

/// Endpoint ID for the default control pipe.
pub const default_control_pipe_id = EndpointId{ .number = 0, .direction = .Out };

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

    pub fn addr(self: EndpointId) u32 {
        return (self.number << 1) + @intFromEnum(self.direction);
    }
};

const EndpointDirection = enum(u1) {
    Out = 0,
    In = 1,
};
