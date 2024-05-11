//! TODO

const std = @import("std");
const Allocator = std.mem.Allocator;
const contexts = @import("context.zig");
const DeviceContext = contexts.DeviceContext;
const Ring = @import("ring.zig").Ring;
const Trb = @import("trb.zig").Trb;

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

        self.devices[slot_id] = self.allocator.create(Device) catch return DeviceError.AllocationFailed;
    }
};

/// USB device.
pub const Device = struct {
    /// Input Context.
    input_context: contexts.InputContext,
    /// Device Context.
    device_context: DeviceContext,
    /// Transfer Rings
    transfer_rings: []?*Ring,

    const Self = @This();

    /// TODO: docs
    pub fn allocTransferRing(self: *Self, dci: usize, size: usize, allocator: Allocator) *Ring {
        const transfer_ring = allocator.create(Ring) catch {
            @panic("Aborting...");
        }; // TODO: return error
        transfer_ring.trbs = allocator.alignedAlloc(Trb, 64, size) catch {
            @panic("Aborting...");
        }; // TODO: return error
        @memset(
            std.mem.asBytes(transfer_ring.trbs.ptr)[0 .. @sizeOf(Trb) * size],
            0,
        );

        self.transfer_rings[dci - 1] = transfer_ring;
        return transfer_ring;
    }

    // unimplemented
};
