//! This file defines xHCI TRB (Transfer Request Block) structures.

const std = @import("std");

/// Template for Trb.
pub const Trb = packed struct(u128) {
    /// Parameter. Ring-specific.
    parameter: u64,
    /// Status. Ring-specific.
    status: u32,
    /// Cycle bit.
    cycle_bit: u1,
    /// Evaluate Next TRB.
    ent: u1,
    /// Ring-specific field.
    _ring_specific: u8,
    /// Type of TRB.
    trb_type: TrbType,
    /// Control. Ring-specific.
    control: u16,

    pub fn clear(self: *Trb) void {
        @memset(std.mem.asBytes(self)[0..@sizeOf(Trb)], 0);
    }
};

pub const PortStatusChangeEventTrb = packed struct(u128) {
    /// Reserved.
    _reserved1: u24 = 0,
    /// Port ID.
    port_id: u8,
    /// Reserved.
    _reserved2: u56 = 0,
    /// Completion Code.
    completion_code: u8,
    /// Cycle bit.
    cycle_bit: u1,
    _reserved3: u9 = 0,
    /// Type of TRB.
    trb_type: TrbType = .PortStatusChange,
    /// Reserved.
    _reserved4: u16 = 0,
};

pub const EnableSlotCommandTrb = packed struct(u128) {
    /// Reserved.
    _reserved1: u96 = 0,
    /// Cycle bit.
    cycle_bit: u1 = 1,
    /// Reserved.
    _reserved2: u9 = 0,
    /// Type of TRB.
    trb_type: TrbType = .EnableSlotCommand,
    /// Slot type.
    slot_type: u5 = 0,
    /// Reserved.
    _reserved3: u11 = 0,
};

pub const LinkTrb = packed struct(u128) {
    /// Reserved.
    _reserved0: u4 = 0,
    /// Ring Segment Pointer.
    ring_segment_pointer: u60,
    /// Reserved
    _reserved1: u22 = 0,
    /// Interrupter Target.
    target: u10 = 0,
    /// Cycle bit.
    cycle_bit: u1 = 1,
    /// Toggle Cycle.
    tc: bool,
    /// Reserved.
    _reserved2: u2 = 0,
    /// Chain Bit.
    ch: bool = false,
    /// Interrupt On Completion.
    ioc: bool = false,
    /// Reserved.
    _reserved3: u4 = 0,
    /// Type of TRB.
    trb_type: TrbType = .Link,
    /// Reserved.
    _reserved4: u16 = 0,
};

pub const CommandCompletionEventTrb = packed struct(u128) {
    /// Command TRB Pointer. Points to the Command TRB that generated this event.
    command_trb_pointer: u64,
    /// Command Completion Parameter.
    command_completion_parameter: u24,
    /// Completion Code.
    completion_code: u8,
    /// Cycle bit.
    cycle_bit: u1,
    /// Reserved.
    _reserved1: u9 = 0,
    /// Type of TRB.
    trb_type: TrbType = .CommandCompletion,
    ///The ID of the Virtual Function that generated this event.
    vf_id: u8 = 0,
    /// The ID of the slot assciated with the command.
    slot_id: u8 = 0,
};

pub const AddressDeviceCommandTrb = packed struct(u128) {
    /// Input Context Pointer.
    input_context_pointer: u64,
    /// Reserved.
    _reserved1: u32 = 0,
    /// Cycle bit.
    cycle_bit: u1 = 1,
    /// Reserved.
    _reserved2: u8 = 0,
    /// Block Set Address Request.
    bsr: bool = false,
    /// Type of TRB.
    trb_type: TrbType = .AddressDeviceCommand,
    /// Reserved.
    _reserved3: u8 = 0,
    /// Slot ID.
    slot_id: u8 = 0,
};

pub const SetupStageTrb = packed struct(u128) {
    // bmRequestType
    bm_request_type: u8,
    /// bRequest
    b_request: u8,
    /// wValue
    w_value: u16,

    /// wIndex
    w_index: u16,
    /// wLength
    w_length: u16,

    /// TRB Transfer Length. Always 8.
    trb_transfer_length: u17 = 8,
    /// Reserved.
    _reserved1: u5 = 0,
    /// Interrupter Target.
    interrupter_target: u10,

    /// Cycle bit.
    cycle_bit: u1 = 1,
    /// Reserved.
    _reserved2: u4 = 0,
    /// Interrupt On Completion.
    ioc: bool = false,
    /// Immediate Data.
    idt: bool = true,
    /// Reserved.
    _reserved3: u3 = 0,
    /// TRB Type.
    trb_type: TrbType = .SetupStage,
    /// Transfer Type.
    trt: TransferType,
    /// Reserved.
    _reserved4: u14 = 0,

    pub const TransferType = enum(u2) {
        NoDataStage = 0,
        OutDataStage = 2,
        InDataStage = 3,
    };
};

pub const DataStageTrb = packed struct(u128) {
    /// TRB Buffer Pointer.
    trb_buffer_pointer: u64,

    /// TRB Transfer Length.
    trb_transfer_length: u17,
    /// TD Size.
    td_size: u5,
    /// Interrupter Target.
    interrupter_target: u10,

    /// Cycle bit.
    cycle_bit: u1 = 1,
    /// Evaluate Next TRB.
    ent: bool = false,
    /// Interrupter on Short Packet.
    isp: bool = false,
    /// No Snoop.
    ns: bool = false,
    /// Chain Bit.
    ch: bool = false,
    /// Interrupt On Completion.
    ioc: bool = false,
    /// Immediate Data.
    idt: bool = false,
    /// Reserved.
    _reserved3: u3 = 0,
    /// TRB Type.
    trb_type: TrbType = .DataStage,
    /// Direction.
    dir: Direction,
    /// Reserved.
    _reserved4: u15 = 0,
};

pub const StatusStageTrb = packed struct(u128) {
    /// Reserved.
    _reserved1: u86 = 0,
    /// Interrupter Target.
    interrupter_target: u10 = 0,

    /// Cycle bit.
    cycle_bit: u1 = 1,
    /// Evaluate Next TRB.
    ent: bool = false,
    /// Reserved.
    _reserved2: u2 = 0,
    /// Chain Bit.
    ch: bool = false,
    /// Interrupt On Completion.
    ioc: bool = false,
    _reserved3: u4 = 0,
    /// TRB Type.
    trb_type: TrbType = .StatusStage,
    /// Direction.
    dir: Direction,
    /// Reserved.
    _reserved4: u15 = 0,
};

pub const TransferEventTrb = packed struct(u128) {
    /// TRB Buffer Pointer.
    trb_pointer: u64,

    /// TRB Transfer Length.
    trb_transfer_length: u24,
    /// Completion Code.
    completion_code: u8,

    /// Cycle bit.
    cycle_bit: u1 = 1,
    /// Reserved.
    _reserved1: u1 = 0,
    /// Event Data.
    /// If set to true, the event was generated by an Event Data TRB.
    /// Otherwise, the pointer to the TRB points to the TRB that generated the event.
    ed: bool,
    /// Reserved.
    _reserved2: u7 = 0,
    /// TRB Type.
    trb_type: TrbType = .Transfer,
    /// Endpoint ID.
    eid: u5,
    /// Reserved.
    _reserved3: u3 = 0,
    /// Slot ID.
    slot_id: u8,
};

/// Type ID of TRB.
pub const TrbType = enum(u6) {
    Reserved = 0,
    Normal = 1,
    SetupStage = 2,
    DataStage = 3,
    StatusStage = 4,
    // ...
    Link = 6,
    // ...
    EnableSlotCommand = 9,
    // ...
    AddressDeviceCommand = 11,
    // ...
    Transfer = 32,
    CommandCompletion = 33,
    PortStatusChange = 34,
    // ...
};

const Direction = enum(u1) {
    Out = 0,
    In = 1,
};
