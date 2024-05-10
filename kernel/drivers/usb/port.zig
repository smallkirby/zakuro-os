//! This file defines the interface for USB Ports.

const PortRegisterSet = @import("register.zig").PortRegisterSet;
const zakuro = @import("zakuro");
const arch = zakuro.arch;

const PortError = error{
    /// Port status is invalid for the operation.
    InvalidState,
};

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
        return self.prs.portsc.read().ccs;
    }

    /// Reset the port.
    /// This operation is necessary for USB2 to make the port 'Enable'.
    /// USB3 essentially does not need it, but has no side effects.
    pub fn reset(self: Self) PortError!void {
        const sc = self.prs.portsc.read();
        if (!(sc.ccs and sc.csc)) {
            return PortError.InvalidState;
        }

        self.prs.portsc.modify(.{
            .pr = true,
            // CSC bit is WR1CS, so we need to write a 1 to clear it.
            .csc = true,
        });

        while (self.prs.portsc.read().pr) {
            arch.relax();
        }
    }
};
