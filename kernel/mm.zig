const std = @import("std");

pub const map = @import("mm/map.zig");

test {
    std.testing.refAllDecls(@This());
}
