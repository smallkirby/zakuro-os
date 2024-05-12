//! TODO

const std = @import("std");
const Allocator = std.mem.Allocator;
const contexts = @import("context.zig");
const DeviceContext = contexts.DeviceContext;
const Ring = @import("ring.zig").Ring;
const Trb = @import("trb.zig").Trb;
const log = std.log.scoped(.device);

pub const DeviceError = error{
    /// The requested slot is already used by other device and port.
    SlotAlreadyUsed,
    /// The requested slot is invalid, exceeding the maximum number of slots.
    InvalidSlot,
    /// Memory allocation failed.
    AllocationFailed,
};

/// Strruct that manages the Devices.
pub const Controller = struct {
    /// The maximum number of Slots that the xHC can have.
    max_slot: usize,
    /// Pointers to the registered devices.
    devices: []?*Device,
    /// DCBAA: Device Context Base Address Array.
    dcbaa: []?*DeviceContext,

    /// Memory allocator used by this controller internally.
    allocator: Allocator,

    const Self = @This();

    pub fn new(max_slot: usize, allocator: Allocator) DeviceError!Self {
        const dcbaa = allocator.alignedAlloc(?*DeviceContext, 64, max_slot + 1) catch return DeviceError.AllocationFailed;
        const devices = allocator.alloc(?*Device, max_slot + 1) catch return DeviceError.AllocationFailed;
        @memset(dcbaa[0..dcbaa.len], null);
        @memset(devices[0..devices.len], null);

        return Self{
            .max_slot = max_slot,
            .dcbaa = dcbaa,
            .devices = devices,
            .allocator = allocator,
        };
    }

    /// Allocate a new device in the specified slot.
    pub fn allocateDevice(self: *Self, slot_id: usize) !void {
        if (self.max_slot < slot_id) {
            return DeviceError.InvalidSlot;
        }
        if (self.devices[slot_id] != null) {
            return DeviceError.SlotAlreadyUsed;
        }

        const device = self.allocator.create(Device) catch return DeviceError.AllocationFailed;
        device.transfer_rings = self.allocator.alloc(?*Ring, 31) catch return DeviceError.AllocationFailed;
        device.slot_id = slot_id;
        self.devices[slot_id] = device;
    }
};

/// USB device.
pub const Device = struct {
    /// Input Context.
    input_context: contexts.InputContext align(64),
    /// Device Context.
    device_context: DeviceContext align(64),
    /// Transfer Rings
    transfer_rings: []?*Ring,
    /// Slot ID
    slot_id: usize,

    const Self = @This();

    /// TODO: docs
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

    // unimplemented
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
