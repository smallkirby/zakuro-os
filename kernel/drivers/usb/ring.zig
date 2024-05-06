//! This file provides a definition of ring buffers.

const Trb = @import("trb.zig").Trb;

/// Ring that can be used both for Command Ring and Transfer Ring.
/// Command Ring is used by software to pass device and HC related command the xHC.
/// Transfer Ring is used by software to schedule work items for a single USB Endpoint.
pub const Ring = struct {
    /// Buffers for TRB.
    trbs: []Trb = undefined,
    /// Cycle Bit for Producer Cycle State.
    pcs: u1 = 1,
    /// Next index to write to.
    index: usize = 0,
};

/// Event Ring that is used by the xHC to pass command completion and async events to software.
pub const EventRing = struct {
    /// Buffers for TRB.
    trbs: []Trb = undefined,
    /// Cycle Bit for Producer Cycle State.
    pcs: u1 = 1,
    /// Next index to write to.
    index: usize = 0,
    /// Event Ring Segment Table.
    erst: []EventRingSegmentTableEntry = undefined,

    // TODO
};

/// Entry in ESRT. ESRT is used to define multi-segment Event Rings,
/// which enables runtime expansion and shrinking of the Event Ring.
pub const EventRingSegmentTableEntry = packed struct(u128) {
    /// Base address of the Event Ring Segment.
    ring_segment_base_addr: u64,
    /// Size of the Event Ring Segment.
    size: u16,
    /// Reserved.
    _reserved: u48,
};
