//! This file defines the Descriptor of USB2/USB3 specs.

/// List of Descriptor Types.
pub const DescriptorType = enum(u8) {
    Device = 1,
};

pub const DeviceDescriptor = packed struct(u144) {
    /// Size of this descriptor in bytes.
    length: u8,
    /// Descriptor type.
    descriptor_type: DescriptorType = .Device,
    /// USB Spec Release Number in Binary-Coded Decimal.
    bcd_usb: u16,
    /// Class code (assigned by the USB-IF).
    device_class: u8,
    /// Subclass code (assigned by the USB-IF).
    device_subclass: u8,
    /// Protocol code (assigned by the USB-IF).
    device_protocol: u8,
    /// Maximum packet size for endpoint 0.
    max_packet_size_0: u8,
    /// Vendor ID (assigned by the USB-IF).
    id_vendor: u16,
    /// Product ID (assigned by the manufacturer).
    id_product: u16,
    /// Device release number in binary-coded decimal.
    bcd_device: u16,
    /// Index of string descriptor describing manufacturer.
    manufacturer: u8,
    /// Index of string descriptor describing product.
    product: u8,
    /// Index of string descriptor describing the device's serial number.
    serial_number: u8,
    /// Number of possible configurations.
    num_configurations: u8,
};
