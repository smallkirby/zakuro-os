//! This file provides Message Signaled Interrupts (MSI) implementation in x64.

/// MSI Address Register
pub const MessageAddress = packed struct(u32) {
    /// Don't care
    _dont_care: u2,
    /// Destination Mode.
    /// If set to Physical, destination ID is LAPIC ID.
    /// If set to Logical, destination ID is a Logical APIC ID.
    dm: DestinationMode,
    /// Redirection Hint.
    /// If set to 0, DM is ignored and always use Physical mode.
    rh: u1,
    /// Reserved.
    _reserved: u8,
    /// Destination ID.
    dest_id: u8,
    /// Always 0xFEE.
    magic: u12 = 0xFEE,
};

/// MSI Data Register
pub const MessageData = packed struct(u64) {
    /// Intrerrupt Vector.
    vector: u8,
    /// Delivery Mode.
    dm: DeliceryMode,
    /// Reserved.
    _reserved1: u3,
    /// Assertion.
    /// If the level for TM is 0, don't care.
    /// If the level for TM is 1, 1 means assert, 0 means deassert.
    assert: bool,
    /// Trigger Mode.
    tm: TriggerMode,
    /// Reserved.
    _reserved2: u48,
};

const DestinationMode = enum(u1) {
    Physical = 0,
    Logical = 1,
};

const DeliceryMode = enum(u3) {
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
