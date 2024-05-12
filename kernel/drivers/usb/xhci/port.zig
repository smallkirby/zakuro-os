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

    /// Returns true if the port is enabled.
    pub fn isEnabled(self: Self) bool {
        return self.prs.portsc.read().ped;
    }

    /// Returns true if the port reset status has changed.
    pub fn isResetChanged(self: Self) bool {
        return self.prs.portsc.read().prc;
    }

    /// Reset the port.
    /// This operation is necessary for USB2 to make the port 'Enable'.
    /// USB3 essentially does not need it, but has no side effects.
    pub fn reset(self: Self) void {
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

/// State of the port and associated slot.
pub const PortState = enum(u8) {
    /// Not connected.
    Disconnected,
    /// Waiting for the slot is addressed
    WaitingAddressed,
    /// Undergoing reset.
    Resetting,
    /// Undergoing enabling slot.
    EnablingSlot,
    /// Undergoing assigning address.
    Addressing,
    /// Undergoing initializing device.
    InitializingDevice,
};
