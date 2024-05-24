//! This module exposes x86_64-specific functions.

pub const serial = @import("serial.zig");
pub const pci = @import("pci.zig");
pub const intr = @import("interrupt.zig");
pub const msi = @import("msi.zig");

const am = @import("asm.zig");

/// Pause a CPU for a short period of time.
pub fn relax() void {
    am.relax();
}

/// Get a BSP(Bootstrap Processor) Local APIC ID.
pub fn getBspLapicId() u8 {
    return @truncate(@as(*u32, @ptrFromInt(0x0FEE_0020)).* >> 24);
}

test {
    @import("std").testing.refAllDeclsRecursive(@This());
}
