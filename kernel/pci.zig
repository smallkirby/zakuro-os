//! TODO

const std = @import("std");
const log = std.log.scoped(.pci);
const arch = @import("arch.zig").impl;

/// List of registered PCI devices.
/// TODO: Remove this global variable and use a dynamically allocated memory.
var devices: [256]?PciDevice = [_]?PciDevice{null} ** 256;
/// Number of registered PCI devices.
/// TODO: Remove this global variable and use a dynamically allocated memory.
var num_devices: u8 = 0;

/// I/O port for configuration address.
pub const addr_configuration_address = 0xCF8;
/// I/O port for configuration data.
pub const addr_configuration_data = 0xCFC;

/// Configration address register.
pub const ConfigAddress = packed struct(u32) {
    offset: u8 = 0,
    function: u3 = 0,
    device: u5 = 0,
    bus: u8 = 0,
    _reserved: u7 = 0,
    /// Enable bit.
    /// If this bit is set, the configuration space of the device is accessible.
    enable: bool = true,

    const Self = @This();

    pub fn as_u32(self: Self) u32 {
        return @as(u32, @bitCast(self));
    }

    pub fn from_u32(v: u32) Self {
        return @as(Self, @bitCast(v));
    }
};

/// Class Code of PCI devices.
/// ref: https://wiki.osdev.org/PCI#Class_Codes
const ClassCodes = enum(u8) {
    Unclassified = 0x00,
    MassStorageController = 0x01,
    NetworkController = 0x02,
    DisplayController = 0x03,
    MultimediaController = 0x04,
    MemoryController = 0x05,
    Bridge = 0x06,
    SimpleCommunicationController = 0x07,
    BaseSystemPeripheral = 0x08,
    InputDeviceController = 0x09,
    DockingStation = 0x0A,
    Processor = 0x0B,
    SerialBusController = 0x0C,
    WirelessController = 0x0D,
    IntelligentController = 0x0E,
    SatelliteCommunicationController = 0x0F,
    EncryptionController = 0x10,
    SignalProcessingController = 0x11,
    ProcessingAccelerator = 0x12,
    NonEssentialInstrumentation = 0x13,
    Coprocessor = 0x40,
    Unassigned = 0xFF,
};

/// Offsets of PCI device header type-0.
const RegisterOffsets = enum(u8) {
    VendorID = 0x00,
    DeviceID = 0x02,
    Command = 0x04,
    Status = 0x06,
    RevisionID = 0x08,
    ProgIF = 0x09,
    Subclass = 0x0A,
    BaseClass = 0x0B,
    CacheLineSize = 0x0C,
    LatencyTimer = 0x0D,
    HeaderType = 0x0E,
    BIST = 0x0F,

    BAR0 = 0x10,
    BAR1 = 0x14,
    BAR2 = 0x18,
    BAR3 = 0x1C,
    BAR4 = 0x20,
    BAR5 = 0x24,
    CardbusCISPointer = 0x28,
    SubsystemVendorID = 0x2C,
    SubsystemID = 0x2E,
    ExpansionROMBaseAddress = 0x30,
    CapabilitiesPointer = 0x34,
    _reserved = 0x35,
    InterruptLine = 0x3C,
    InterruptPin = 0x3D,
    MinGrant = 0x3E,
    MaxLatency = 0x3F,

    pub fn RegisterWidth(comptime reg: @This()) type {
        return switch (reg) {
            .RevisionID,
            .ProgIF,
            .Subclass,
            .BaseClass,
            .CacheLineSize,
            .LatencyTimer,
            .HeaderType,
            .BIST,
            .CapabilitiesPointer,
            .InterruptLine,
            .InterruptPin,
            .MinGrant,
            .MaxLatency,
            => u32,
            .VendorID,
            .DeviceID,
            .Command,
            .Status,
            .SubsystemID,
            .SubsystemVendorID,
            => u16,
            .BAR0,
            .BAR1,
            .BAR2,
            .BAR3,
            .BAR4,
            .BAR5,
            .CardbusCISPointer,
            .ExpansionROMBaseAddress,
            => u32,
            else => unreachable,
        };
    }
};

/// PCI device.
pub const PciDevice = struct {
    bus: u8,
    device: u5,

    const Self = @This();

    /// Get the configuration address of the device.
    pub fn address(self: Self, function: u3, reg: RegisterOffsets) ConfigAddress {
        return ConfigAddress{
            .offset = @intFromEnum(reg),
            .function = function,
            .device = self.device,
            .bus = self.bus,
        };
    }

    /// Read data from the configuration space of the device.
    pub fn read_data(
        self: Self,
        function: u3,
        comptime reg: RegisterOffsets,
    ) reg.RegisterWidth() {
        const addr = self.address(function, reg);
        arch.pci.set_config_address(addr);
        const val = arch.pci.get_config_data();

        return @truncate(val >> (@intFromEnum(reg) % 4 * 8));
    }

    /// Check if the device is a single-function device.
    pub fn is_single_function(self: Self) bool {
        const header_type = self.read_data(0, RegisterOffsets.HeaderType);
        return (header_type & 0x80) == 0;
    }

    /// Read a 16-bit Vendor ID of the device from the configuration space.
    pub fn read_vendor_id(self: Self, function: u3) u16 {
        return self.read_data(function, RegisterOffsets.VendorID);
    }

    /// Read a 16-bit Device ID of the device from the configuration space.
    pub fn read_device_id(self: Self, function: u3) u16 {
        return self.read_data(function, RegisterOffsets.DeviceID);
    }

    /// Read a 8-bit Header Type of the device from the configuration space.
    fn read_header_type(self: Self, function: u3) u8 {
        return self.read_data(function, RegisterOffsets.HeaderType);
    }

    /// Read bus numbers from the configuration space of bridge devices (Header Type = 1 or 2).
    fn read_bus_number(self: Self, function: u3) u32 {
        const addr = ConfigAddress{
            .offset = 0x18,
            .function = function,
            .device = self.device,
            .bus = self.bus,
        };

        arch.pci.set_config_address(addr);
        return arch.pci.get_config_data();
    }
};

fn register_function(bus: u8, device: u5, function: u3) void {
    const dev = PciDevice{ .bus = bus, .device = device };
    const base_class = dev.read_data(function, RegisterOffsets.BaseClass);
    const subclass = dev.read_data(function, RegisterOffsets.Subclass);

    // TODO: register device here
    log.info("PCI: {X:0>2}:{X:0>2}:{X:0>2}", .{ bus, device, function });

    if (base_class == @intFromEnum(ClassCodes.Bridge) and subclass == 0x04) {
        // this is a PCI-to-PCI bridge
        const bus_number = dev.read_bus_number(function);
        const secondary_bus: u8 = @truncate(bus_number >> 8);
        register_bus(secondary_bus);
    }
}

fn register_device(bus: u8, device: u5) void {
    const dev = PciDevice{ .bus = bus, .device = device };
    if (dev.read_vendor_id(0) == 0xFFFF) return;

    register_function(bus, device, 0);

    if (dev.is_single_function()) return;
    for (1..8) |function| {
        if (dev.read_vendor_id(@truncate(function)) != 0xFFFF) {
            register_function(bus, device, @truncate(function));
        }
    }
}

fn register_bus(bus: u8) void {
    for (0..32) |device| {
        register_device(bus, @truncate(device));
    }
}

/// Scan all PCI devices and register them.
/// Note that it clears the device list before scanning.
/// Note: There are three ways to scan PCI devices.
/// The first is to brute-force all possible devices(32*256).
/// The second is a recursive scan that finds available buses while scanning.
/// The last one is similar to the second, but configures registers while scanning.
/// This function uses the second method.
/// TODO: After kheap allocator is implemented, we should dynamically allocate memory for the device list.
pub fn register_all_devices() void {
    // Clear the device list.
    num_devices = 0;
    @memset(&devices, null);

    // Recursively scan all devices under valid buses.
    const bridge = PciDevice{ .bus = 0, .device = 0 };
    if (bridge.is_single_function()) {
        register_bus(0);
    } else {
        for (0..8) |function| {
            if (bridge.read_vendor_id(@truncate(function)) == 0xFFFF) {
                continue;
            }
            register_bus(@truncate(function));
        }
    }
}

/////////////////////////////////////

const expectEqual = std.testing.expectEqual;

test "ConfigAddress cast" {
    const addr = ConfigAddress{
        .offset = 0b0010_0000,
        .function = 0b101,
        .device = 0b11010,
        .bus = 0b10001011,
    };

    try expectEqual(0b1_0000000_10001011_11010_101_00100000, addr.as_u32());
    try expectEqual(addr, ConfigAddress.from_u32(addr.as_u32()));
}
