//! This module exposes x86_64-specific functions.

pub const serial = @import("serial.zig");
pub const pci = @import("pci.zig");
const am = @import("asm.zig");

/// Pause a CPU for a short period of time.
pub fn relax() void {
    am.relax();
}
