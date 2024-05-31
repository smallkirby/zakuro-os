//! Libraries for common data structures and algorithms.

const std = @import("std");

pub const queue = @import("lib/queue.zig");

test {
    std.testing.refAllDecls(@This());
}
