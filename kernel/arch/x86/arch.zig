//! This module exposes x86_64-specific functions.

pub const serial = @import("serial.zig");
pub const pci = @import("pci.zig");
pub const intr = @import("interrupt.zig");
pub const msi = @import("msi.zig");
pub const gdt = @import("gdt.zig");
pub const page = @import("page.zig");
pub const timer = @import("timer.zig");

const am = @import("asm.zig");
const apic = @import("apic.zig");
const acpi = @import("acpi.zig");

pub const Rsdp = acpi.Rsdp;

/// Page size.
pub const page_size: usize = 4096;
/// Page shift in bits.
pub const page_shift: usize = 12;
/// Page mask.
pub const page_mask: usize = page_size - 1;

pub const getLapicId = apic.getLapicId;
pub const notifyEoi = apic.notifyEoi;

/// Pause a CPU for a short period of time.
pub fn relax() void {
    am.relax();
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

/// Port I/O In instruction.
pub inline fn in(T: type, port: u16) T {
    return switch (T) {
        u8 => am.inb(port),
        u16 => am.inw(port),
        u32 => am.inl(port),
        else => @compileError("Unsupported type for asm in()"),
    };
}

test {
    @import("std").testing.refAllDeclsRecursive(@This());
}
