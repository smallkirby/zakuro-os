//! This file provides x64 Local APIC register definitions.

/// Local APIC ID registers
pub const lapic_id_register: u64 = 0xFEE0_0020;
/// Local APIC version register
pub const lapic_version_register: u64 = 0xFEE0_0030;
/// Task Priority Register
pub const tpr: u64 = 0xFEE0_0080;
/// Arbitration Priority Register
pub const apr: u64 = 0xFEE0_0090;
/// Processor Priority Register
pub const ppr: u64 = 0xFEE0_00A0;
/// EOI Register
pub const eoi: u64 = 0xFEE0_00B0;
/// LVT (Local Vector Table) Timer Register
pub const lvt_timer_register: u64 = 0xFEE0_0320;
/// Initial Count Register for Timer
pub const initial_count_register: u64 = 0xFEE0_0380;
/// Current Count Register for Timer
pub const current_count_register: u64 = 0xFEE0_0390;
/// Divide Configuration Register for Timer
pub const divide_config_register: u64 = 0xFEE0_03E0;

/// Get a Local APIC ID of the current core.
pub fn getLapicId() u8 {
    return @truncate(@as(*u32, @ptrFromInt(lapic_id_register)).* >> 24);
}

/// Notify the LAPIC that the interrupt has been handled.
pub fn notifyEoi() void {
    @as(*volatile u32, @ptrFromInt(eoi)).* = 0;
}
