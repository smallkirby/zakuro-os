//! This file defines xHCI TRB (Transfer Request Block) structures.

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
    trb_type: u6,
    /// Control. Ring-specific.
    control: u16,
};
