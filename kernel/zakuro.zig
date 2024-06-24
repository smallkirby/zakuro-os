//! The functions and modules in this file are used throughout the codebase.

pub const pci = @import("pci.zig");
pub const log = @import("log.zig");
pub const serial = @import("serial.zig");
pub const console = @import("console.zig");
pub const gfx = @import("gfx.zig");
pub const color = @import("color.zig");
pub const arch = @import("arch.zig").impl;
pub const font = @import("font.zig");
pub const drivers = @import("drivers.zig");
pub const mmio = @import("mmio.zig");
pub const mouse = @import("mouse.zig");
pub const mm = @import("mm.zig");
pub const timer = @import("timer.zig");
pub const event = @import("event.zig");

pub const lib = @import("lib.zig");

pub const dwarf = @import("dwarf/dwarf.zig");

/// 2D vector.
pub fn Vector(comptime T: type) type {
    return struct {
        x: T,
        y: T,
    };
}

test {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
