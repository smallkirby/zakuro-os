//! This file defines the Descriptor of USB2/USB3 specs.

/// List of Descriptor Types.
pub const DescriptorType = enum(u8) {
    Device = 1,
    Configuration = 2,
    Interface = 4,
    Endpoint = 5,
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

pub const ConfigurationDescriptor = packed struct(u72) {
    /// Size of this descriptor in bytes.
    length: u8,
    /// Descriptor type.
    descriptor_type: DescriptorType = .Configuration,
    /// Total length of data returned for this configuration.
    total_length: u16,
    /// Number of interfaces supported by this configuration.
    num_interfaces: u8,
    /// Value to select this configuration with SetConfiguration request.
    configuration_value: u8,
    /// Index of string descriptor describing this configuration.
    configuration: u8,
    /// Configuration characteristics.
    attributes: Attribute,
    /// Maximum power consumption of the USB device from the bus in this configuration when the device is fully operational.
    max_power: u8,

    pub const Attribute = packed struct(u8) {
        _reserved1: u5,
        remote_wakeup: bool,
        self_powered: bool,
        _reserved2: u1,
    };
};

pub const InterfaceDescriptor = packed struct(u72) {
    /// Size of this descriptor in bytes.
    length: u8,
    /// Descriptor type.
    descriptor_type: DescriptorType = .Interface,
    /// Zero-origin Number(index) of this interface.
    interface_number: u8,
    /// Value used to select this alternate setting for the interface supported by this configuration.
    alternate_setting: u8,
    /// Number of endpoints used by this interface (excluding endpoint zero).
    num_endpoints: u8,
    /// Class code (assigned by the USB-IF).
    interface_class: u8,
    /// Subclass code (assigned by the USB-IF).
    interface_subclass: u8,
    /// Protocol code (assigned by the USB).
    interface_protocol: u8,
    /// Index of string descriptor describing this interface.
    interface: u8,
};

pub const EndpointDescriptor = packed struct(u56) {
    /// Size of this descriptor in bytes.
    length: u8,
    /// Descriptor type.
    descriptor_type: DescriptorType = .Endpoint,
    /// Address of the endpoint on the USB device.
    endpoint_address: u8,
    /// Attributes of the endpoint.
    attributes: Attribute,
    /// Maximum packet size this endpoint is capable of sending or receiving when this configuration is selected.
    max_packet_size: u16,
    /// Interval for polling endpoint for data transfers.
    interval: u8,

    pub const Attribute = packed struct(u8) {
        transfer_type: TransferType,
        sync_type: SyncType,
        usage_type: UsageType,
        _reserved: u2,
    };

    pub const TransferType = enum(u2) {
        Control = 0,
        Isochronous = 1,
        Bulk = 2,
        Interrupt = 3,
    };

    pub const SyncType = enum(u2) {
        NoSync = 0,
        Async = 1,
        Adaptive = 2,
        Sync = 3,
    };

    pub const UsageType = enum(u2) {
        Data = 0,
        Feedback = 1,
        ImplicitFeedbackData = 2,
    };
};
