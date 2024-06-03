const std = @import("std");

pub const uefi = @import("mm/uefi.zig");

test {
    std.testing.refAllDecls(@This());
}
