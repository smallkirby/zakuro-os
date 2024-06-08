//! This module exposes x86_64-specific functions.

pub const serial = @import("serial.zig");
pub const pci = @import("pci.zig");
pub const intr = @import("interrupt.zig");
pub const msi = @import("msi.zig");
pub const gdt = @import("gdt.zig");
pub const page = @import("page.zig");

const am = @import("asm.zig");

/// Page size.
pub const page_size: usize = 4096;
/// Page shift in bits.
pub const page_shift: usize = 12;
/// Page mask.
pub const page_mask: usize = page_size - 1;

/// Pause a CPU for a short period of time.
pub fn relax() void {
    am.relax();
}

/// Get a BSP(Bootstrap Processor) Local APIC ID.
pub fn getBspLapicId() u8 {
    return @truncate(@as(*u32, @ptrFromInt(0x0FEE_0020)).* >> 24);
}

/// Disable interrupts.
/// Note that exceptions and NMI are not ignored.
pub inline fn disableIntr() void {
    am.cli();
}

/// Enable interrupts.
pub inline fn enableIntr() void {
    am.sti();
}

/// Halt the current CPU.
pub inline fn halt() void {
    am.hlt();
}

test {
    @import("std").testing.refAllDeclsRecursive(@This());
}
