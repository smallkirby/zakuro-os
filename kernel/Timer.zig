const std = @import("std");
const Allocator = std.mem.Allocator;

const zakuro = @import("zakuro");
const arch = zakuro.arch;

pub const Timer = Self;
const Self = @This();

/// Total tick count.
total_tick: u64,

/// Initialize a Local APIC timer.
pub fn init(vector: u8, allocator: Allocator) !*Self {
    const self = try allocator.create(Self);
    self.* = Self{
        .total_tick = 0,
    };

    arch.timer.init(vector, 0x01000_0000);

    return self;
}

/// Increment the tick count by one.
pub fn tick(self: *Self) void {
    self.total_tick += 1;
}
