//! This file provides a xHCI Device.
//! Note that this device is at lower level than the USB Device.

const std = @import("std");
const Allocator = std.mem.Allocator;
const contexts = @import("context.zig");
const DeviceContext = contexts.DeviceContext;
const Ring = @import("ring.zig").Ring;
const Trb = @import("trb.zig").Trb;
const log = std.log.scoped(.device);

/// xHCI device.
pub const XhciDevice = struct {
    /// Input Context.
    input_context: contexts.InputContext align(64),
    /// Device Context.
    device_context: DeviceContext align(64),
    /// Transfer Rings
    transfer_rings: []?*Ring,
    /// Slot ID
    slot_id: usize,

    const Self = @This();

    /// Allocate a Transfer Ring for the specified Endpoint.
    pub fn allocTransferRing(self: *Self, dci: usize, size: usize, allocator: Allocator) *Ring {
        const transfer_rings = allocator.alignedAlloc(Ring, 64, 1) catch {
            @panic("Aborting...");
        }; // TODO: return error
        const tr = &transfer_rings[0];
        const trbs = allocator.alignedAlloc(Trb, 64, size) catch {
            @panic("Aborting...");
        }; // TODO: return error
        for (trbs) |*trb| {
            trb.clear();
        }
        tr.init(trbs);

        self.transfer_rings[dci - 1] = tr;
        return tr;
    }
};

/// Direction of the Endpoint Context.
pub const EpContextDirection = enum(u8) {
    Out = 0,
    In = 1,
    /// Used only for EP Context 0.
    InOut,
    /// Used only for Slot Context.
    Slot,
};

/// Calculate the DCI (Device Context Index) for the specified Endpoint.
pub fn calcDci(ep_index: u8, direction: EpContextDirection) u5 {
    if (direction == .InOut and ep_index != 0)
        @panic("InOut direction is only valid for EP Context 0");
    if (direction == .Slot)
        @panic("You cannot use this function to get the DCI for the Slot Context.");

    return if (ep_index == 0) 1 else @as(u5, @truncate(ep_index * 2)) + @as(u5, @truncate(@intFromEnum(direction)));
}

/// Calculate the Max Packet Size from the slot speed.
pub fn calcMaxPacketSize(slot_speed: u8) u16 {
    return switch (slot_speed) {
        4 => 512,
        3 => 64,
        else => 8,
    };
}
