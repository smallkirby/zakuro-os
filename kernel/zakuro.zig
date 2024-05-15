//! The functions and modules in this file are used throughout the codebase.

pub const pci = @import("pci.zig");
pub const log = @import("log.zig");
pub const serial = @import("serial.zig");
pub const console = @import("console.zig");
pub const graphics = @import("graphics.zig");
pub const color = @import("color.zig");
pub const arch = @import("arch.zig").impl;
pub const font = @import("font.zig");
pub const drivers = @import("drivers.zig");
pub const mmio = @import("mmio.zig");

test {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
