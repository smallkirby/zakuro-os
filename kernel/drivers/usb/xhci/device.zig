//! This file provides a xHCI Device.
//! Note that this device is at lower level than the USB Device.

const std = @import("std");
const Allocator = std.mem.Allocator;
const contexts = @import("context.zig");
const DeviceContext = contexts.DeviceContext;
const Ring = @import("ring.zig").Ring;
const Trb = @import("trb.zig").Trb;
const regs = @import("register.zig");
const log = std.log.scoped(.device);
const zakuro = @import("zakuro");
const setupdata = zakuro.drivers.usb.setupdata;
const endpoint = zakuro.drivers.usb.endpoint;
const descriptor = zakuro.drivers.usb.descriptor;
const UsbDevice = zakuro.drivers.usb.device.UsbDevice;
const Register = zakuro.mmio.Register;

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
    devices: []?*UsbDevice,
    /// DCBAA: Device Context Base Address Array.
    dcbaa: []?*DeviceContext,

    /// Memory allocator used by this controller internally.
    allocator: Allocator,

    const Self = @This();

    pub fn new(
        max_slot: usize,
        allocator: Allocator,
    ) DeviceError!Self {
        const dcbaa = allocator.alignedAlloc(?*DeviceContext, 64, max_slot + 1) catch return DeviceError.AllocationFailed;
        const devices = allocator.alloc(?*UsbDevice, max_slot + 1) catch return DeviceError.AllocationFailed;
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
    pub fn allocateDevice(
        self: *Self,
        slot_id: usize,
        db: *volatile Register(regs.DoorbellRegister, .DWORD),
    ) !void {
        if (self.max_slot < slot_id) {
            return DeviceError.InvalidSlot;
        }
        if (self.devices[slot_id] != null) {
            return DeviceError.SlotAlreadyUsed;
        }

        const device = self.allocator.create(UsbDevice) catch return DeviceError.AllocationFailed;
        device.dev.transfer_rings = self.allocator.alloc(?*Ring, 31) catch return DeviceError.AllocationFailed;
        device.dev.slot_id = slot_id;
        device.db = db;
        self.devices[slot_id] = device;
    }
};

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
