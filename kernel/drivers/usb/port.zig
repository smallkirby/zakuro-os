//! This file defines the interface for USB Ports.

const PortRegisterSet = @import("register.zig").PortRegisterSet;

/// xHCI USB Port.
pub const Port = struct {
    /// Index of the port.
    port_index: usize,
    /// Port status and control registers.
    prs: *PortRegisterSet,

    const Self = @This();

    /// Create a new port interface.
    pub fn new(port_index: usize, prs: *PortRegisterSet) Self {
        return Self{
            .port_index = port_index,
            .prs = prs,
        };
    }

    /// Returns true if the port is connected.
    pub fn isConnected(self: Self) bool {
        return self.prs.portsc.ccs;
    }
};
