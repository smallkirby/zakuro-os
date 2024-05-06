//! TODO

const std = @import("std");
const zakuro = @import("zakuro");
const log = std.log.scoped(.pci);
const arch = zakuro.arch;

/// Maximum number of PCI devices that can be registered.
const max_device_num: usize = 256;
/// List of registered PCI devices.
/// TODO: Remove this global variable and use a dynamically allocated memory.
pub var devices: [max_device_num]?DeviceInfo = [_]?DeviceInfo{null} ** max_device_num;
/// Number of registered PCI devices.
/// TODO: Remove this global variable and use a dynamically allocated memory.
pub var num_devices: usize = 0;

/// I/O port for configuration address.
pub const addr_configuration_address = 0xCF8;
/// I/O port for configuration data.
pub const addr_configuration_data = 0xCFC;

/// List of available errors.
pub const PciError = error{
    /// Device list is full.
    ListFull,
};

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

/// Base class Code of PCI devices.
/// ref: https://wiki.osdev.org/PCI#Class_Codes
pub const ClassCodes = enum(u8) {
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

    pub fn Width(comptime reg: @This()) type {
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
            => u8,
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
    pub fn readData(
        self: Self,
        function: u3,
        comptime reg: RegisterOffsets,
    ) reg.Width() {
        const addr = self.address(function, reg);
        arch.pci.setConfigAddress(addr);
        const val = arch.pci.getConfigData();

        return @truncate(val >> (@intFromEnum(reg) % 4 * 8));
    }

    /// Check if the device is a single-function device.
    pub fn isSingleFunction(self: Self) bool {
        const header_type = self.readData(0, RegisterOffsets.HeaderType);
        return (header_type & 0x80) == 0;
    }

    /// Read a 16-bit Vendor ID of the device from the configuration space.
    pub fn readVendorId(self: Self, function: u3) u16 {
        return self.readData(function, RegisterOffsets.VendorID);
    }

    /// Read a 16-bit Device ID of the device from the configuration space.
    pub fn readDeviceId(self: Self, function: u3) u16 {
        return self.readData(function, RegisterOffsets.DeviceID);
    }

    /// Read a 32-bit BAR (Base Address Register) of the device from the configuration space.
    pub fn readBar(self: Self, function: u3, comptime index: u3) u32 {
        const offset: u8 = @intFromEnum(RegisterOffsets.BAR0) + @as(u8, index) * 4;
        const addr = ConfigAddress{
            .offset = offset,
            .function = function,
            .device = self.device,
            .bus = self.bus,
        };
        arch.pci.setConfigAddress(addr);
        return arch.pci.getConfigData();
    }

    /// Read a various information of the device from the configuration space.
    pub fn readDeviceInfo(self: Self, function: u3) ?DeviceInfo {
        const vendor_id = self.readVendorId(function);
        if (vendor_id == 0xFFFF) {
            return null;
        }
        const revision_id = self.readData(function, RegisterOffsets.RevisionID);
        const base_class = self.readData(function, RegisterOffsets.BaseClass);
        const subclass = self.readData(function, RegisterOffsets.Subclass);
        const prog_if = self.readData(function, RegisterOffsets.ProgIF);
        const header_type = self.readHeaderType(function);

        return .{
            .device = self,
            .function = function,
            .vendor_id = vendor_id,
            .revision_id = revision_id,
            .base_class = base_class,
            .subclass = subclass,
            .prog_if = prog_if,
            .header_type = header_type,
        };
    }

    /// Read a 8-bit Header Type of the device from the configuration space.
    fn readHeaderType(self: Self, function: u3) u8 {
        return self.readData(function, RegisterOffsets.HeaderType);
    }

    /// Read bus numbers from the configuration space of bridge devices (Header Type = 1 or 2).
    fn readBusNumber(self: Self, function: u3) u32 {
        const addr = ConfigAddress{
            .offset = 0x18,
            .function = function,
            .device = self.device,
            .bus = self.bus,
        };

        arch.pci.setConfigAddress(addr);
        return arch.pci.getConfigData();
    }
};

/// Device information including BDF and other specs.
/// One function of a PCI device corresponds to one DeviceInfo.
pub const DeviceInfo = struct {
    /// PCI device.
    device: PciDevice,
    /// Function number that this DeviceInfo represents.
    function: u3,
    /// Vendor ID
    vendor_id: u16,
    /// Revision ID
    revision_id: u8,
    /// Base class code
    base_class: u8,
    /// Subclass code
    subclass: u8,
    /// Program interface
    prog_if: u8,
    /// Header type
    header_type: u8,
};

/// Add a PCI device to the known device list.
fn addDevice(device: PciDevice, function: u3) PciError!void {
    if (num_devices >= max_device_num) {
        return PciError.ListFull;
    }

    const info = device.readDeviceInfo(function);
    devices[num_devices] = info;
    num_devices += 1;
}

fn registerFunction(bus: u8, device: u5, function: u3) PciError!void {
    const dev = PciDevice{ .bus = bus, .device = device };
    const base_class = dev.readData(function, RegisterOffsets.BaseClass);
    const subclass = dev.readData(function, RegisterOffsets.Subclass);

    // TODO: register device here
    try addDevice(dev, function);

    if (base_class == @intFromEnum(ClassCodes.Bridge) and subclass == 0x04) {
        // this is a PCI-to-PCI bridge
        const bus_number = dev.readBusNumber(function);
        const secondary_bus: u8 = @truncate(bus_number >> 8);
        try registerBus(secondary_bus);
    }
}

fn registerDevice(bus: u8, device: u5) PciError!void {
    const dev = PciDevice{ .bus = bus, .device = device };
    if (dev.readVendorId(0) == 0xFFFF) return;

    try registerFunction(bus, device, 0);

    if (dev.isSingleFunction()) return;
    for (1..8) |function| {
        if (dev.readVendorId(@truncate(function)) != 0xFFFF) {
            try registerFunction(bus, device, @truncate(function));
        }
    }
}

fn registerBus(bus: u8) PciError!void {
    for (0..32) |device| {
        try registerDevice(bus, @truncate(device));
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
pub fn registerAllDevices() PciError!void {
    // Clear the device list.
    num_devices = 0;
    @memset(&devices, null);

    // Recursively scan all devices under valid buses.
    const bridge = PciDevice{ .bus = 0, .device = 0 };
    if (bridge.isSingleFunction()) {
        try registerBus(0);
    } else {
        for (0..8) |function| {
            if (bridge.readVendorId(@truncate(function)) == 0xFFFF) {
                continue;
            }
            try registerBus(@truncate(function));
        }
    }
}

pub const KnownVendors = enum(u16) {
    Intel = 0x8086,
    Nec = 0x1033,
    Qemu = 0x1234,
};

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
