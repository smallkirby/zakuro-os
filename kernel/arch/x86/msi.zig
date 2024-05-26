//! This file provides Message Signaled Interrupts (MSI) implementation in x64.

/// Capability register in MMIO configuration space for MSI.
pub const CapabilityRegister = packed struct(u128) {
    /// Capability ID. 0x05 for MSI.
    cap_id: u8 = 0x05,
    /// Offset of the next capability.
    next_ptr: u8,
    /// MSI Enable.
    enable: bool = true,
    /// Multiple Message Capable: the maximum number of interrupt vectors.
    multi_msg_capable: u3,
    /// Multiple Message Enable: the number of interrupt vectors in exponential form.
    multi_msg_enable: u3,
    /// 64-bit Address Capable.
    enable64: bool = false,
    /// Per-vector Masking Capable.
    pvmcap: bool = false,
    /// Unimplemented.
    _unimplemented: u7 = 0,

    /// Message address lower 32 bits.
    msg_addr: MessageAddress,
    /// Message address upper 32 bits.
    /// Iff 64-bit capable, this field is valid.
    msg_addr_upper: u32 = 0,

    /// Message data.
    msg_data: MessageData,
};

/// MSI Address Register
pub const MessageAddress = packed struct(u32) {
    /// Don't care
    _dont_care: u2 = 0,
    /// Destination Mode.
    /// If set to Physical, destination ID is LAPIC ID.
    /// If set to Logical, destination ID is a Logical APIC ID.
    dm: DestinationMode = .Physical,
    /// Redirection Hint.
    /// If set to 0, DM is ignored and always use Physical mode.
    rh: u1 = 0,
    /// Reserved.
    _reserved: u8 = 0,
    /// Destination ID.
    dest_id: u8,
    /// Always 0xFEE.
    magic: u12 = 0xFEE,
};

/// MSI Data Register
pub const MessageData = packed struct(u32) {
    /// Intrerrupt Vector.
    vector: u8,
    /// Delivery Mode.
    dm: DeliveryMode = .Fixed,
    /// Reserved.
    _reserved1: u3 = 0,
    /// Assertion.
    /// If the level for TM is 0, don't care.
    /// If the level for TM is 1, 1 means assert, 0 means deassert.
    assert: bool,
    /// Trigger Mode.
    tm: TriggerMode = .Level,
    /// Reserved.
    _reserved2: u16 = 0,
};

const DestinationMode = enum(u1) {
    Physical = 0,
    Logical = 1,
};

const DeliveryMode = enum(u3) {
    Fixed = 0b000,
    LowestPriority = 0b001,
    SMI = 0b010,
    Reserved1 = 0b011,
    NMI = 0b100,
    INIT = 0b101,
    Reserved2 = 0b110,
    ExtINT = 0b111,
};

const TriggerMode = enum(u1) {
    Edge = 0,
    Level = 1,
};
