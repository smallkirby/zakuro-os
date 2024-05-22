const std = @import("std");

/// Entry in the Interrupt Descriptor Table.
pub const GateDesriptor = packed struct(u128) {
    /// Lower 16 bits of the offset to the ISR.
    offset_low: u16,
    /// Segment Selector that must point to a valid code segment in the GDT.
    seg_selector: u16,
    /// Interrupt Stack Table. Not used.
    ist: u3 = 0,
    /// Reserved.
    _reserved1: u5 = 0,
    /// Gate Type.
    gate_type: GateType,
    /// Reserved.
    _reserved2: u1 = 0,
    /// Descriptor Privilege Level is the required CPL to call the ISR via the INT inst.
    /// Hardware interrupts ignore this field.
    dpl: u2,
    /// Present flag. Must be 1.
    present: bool = true,
    /// Middle 16 bits of the offset to the ISR.
    offset_middle: u16,
    /// Higher 32 bits of the offset to the ISR.
    offset_high: u32,
    /// Reserved.
    _reserved3: u32 = 0,

    pub fn offset(self: GateDesriptor) u64 {
        return @as(u64, self.offset_high) << 32 | @as(u64, self.offset_middle) << 16 | @as(u64, self.offset_low);
    }
};

/// Gate type of the gate descriptor in IDT.
pub const GateType = enum(u4) {
    Interrupt64 = 0b1110,
    Trap64 = 0b1111,
};

const testing = std.testing;

test "gate descriptor" {
    const gate = GateDesriptor{
        .offset_low = 0x1234,
        .seg_selector = 0x5678,
        .gate_type = .Interrupt64,
        .offset_middle = 0x9abc,
        .offset_high = 0x0123def0,
        .dpl = 0,
    };

    try testing.expectEqual(0x0123def0_9abc_1234, gate.offset());
}
