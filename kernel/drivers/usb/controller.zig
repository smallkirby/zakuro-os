//! TODO

const std = @import("std");
const Allocator = std.mem.Allocator;
const contexts = @import("xhci/context.zig");
const DeviceContext = contexts.DeviceContext;
const Ring = @import("xhci/ring.zig").Ring;
const regs = @import("xhci/register.zig");
const zakuro = @import("zakuro");
const UsbDevice = zakuro.drivers.usb.device.UsbDevice;
const Register = zakuro.mmio.Register;

pub const ControllerError = error{
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
    ) ControllerError!Self {
        const dcbaa = allocator.alignedAlloc(?*DeviceContext, 64, max_slot + 1) catch return ControllerError.AllocationFailed;
        const devices = allocator.alloc(?*UsbDevice, max_slot + 1) catch return ControllerError.AllocationFailed;
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
            return ControllerError.InvalidSlot;
        }
        if (self.devices[slot_id] != null) {
            return ControllerError.SlotAlreadyUsed;
        }

        const device = self.allocator.create(UsbDevice) catch return ControllerError.AllocationFailed;
        device.dev.transfer_rings = self.allocator.alloc(?*Ring, 31) catch return ControllerError.AllocationFailed;
        device.dev.slot_id = slot_id;
        device.db = db;
        self.devices[slot_id] = device;
    }
};
