//! This file provides a definition of ring buffers.

const Trb = @import("trb.zig").Trb;
const LinkTrb = @import("trb.zig").LinkTrb;
const regs = @import("register.zig");
const std = @import("std");
const log = std.log.scoped(.ring);

/// Ring that can be used both for Command Ring and Transfer Ring.
/// Command Ring is used by software to pass device and HC related command the xHC.
/// Transfer Ring is used by software to schedule work items for a single USB Endpoint.
pub const Ring = struct {
    /// Buffers for TRB.
    trbs: []Trb = undefined,
    /// Cycle Bit for Producer Cycle State.
    pcs: u1 = 1,
    /// Next index to write to.
    index: usize = 0,

    /// Copy a TRB to the tail of the Ring pointed to by the index.
    fn copyToTail(self: *Ring, new_trb: *Trb) void {
        // Set the cycle bit.
        new_trb.cycle_bit = self.pcs;

        // Copy the TRB.
        const new_bytes: [*]u32 = @ptrCast(std.mem.asBytes(new_trb));
        const trb = &self.trbs[self.index];
        const trb_bytes: [*]volatile u32 = @ptrCast(trb);
        for (0..4) |i| {
            trb_bytes[i] = new_bytes[i];
        }
    }

    pub fn init(self: *Ring, trbs: []Trb) void {
        self.pcs = 1;
        self.index = 0;
        self.trbs = trbs;
    }

    /// Enqueue a TRB to the Ring.
    /// CRB of the TRB is properly set.
    /// TRB is copied, so the argument can be located in the stack.
    pub fn push(self: *Ring, new_trb: *Trb) *Trb {
        // Copy the TRB to the tail of the Ring.
        self.copyToTail(new_trb);

        const trb = &self.trbs[self.index];

        // Increment cursor.
        self.index += 1;
        if (self.index == self.trbs.len - 1) {
            var link = LinkTrb{
                .ring_segment_pointer = @truncate(@as(u64, @intFromPtr(self.trbs.ptr)) >> 4),
                .tc = true,
            };
            self.copyToTail(@ptrCast(&link));
            self.pcs +%= 1;
            self.index = 0;
        }

        return trb;
    }
};

/// Event Ring that is used by the xHC to pass command completion and async events to software.
pub const EventRing = struct {
    /// Buffers for TRB.
    trbs: []Trb = undefined,
    /// Cycle Bit for Producer Cycle State.
    pcs: u1 = 1,
    /// Event Ring Segment Table.
    erst: *[1]EventRingSegmentTableEntry = undefined,
    /// Interrupter Register Set that this Event Ring belongs to.
    interrupter: *volatile regs.InterrupterRegisterSet = undefined,

    const Self = @This();

    /// Check if more than one event is queued in the Event Ring.
    pub fn hasEvent(self: *Self) bool {
        return self.front().cycle_bit == self.pcs;
    }

    /// Get the TRB pointed to by the Interrupter's dequeue pointer.
    pub fn front(self: *Self) *volatile Trb {
        return @ptrFromInt(self.interrupter.erdp & ~@as(u64, 0b1111));
    }

    /// Pop the front TRB.
    pub fn pop(self: *Self) void {
        // Intcement ERDP
        var p: *volatile Trb = @ptrFromInt((self.interrupter.erdp & ~@as(u64, 0b1111)) + @sizeOf(Trb));
        const begin: *volatile Trb = @ptrFromInt(self.erst[0].ring_segment_base_addr);
        const end: *volatile Trb = @ptrFromInt(self.erst[0].ring_segment_base_addr + self.erst[0].size * @sizeOf(Trb));
        if (p == end) {
            p = begin;
            self.pcs +%= 1;
        }

        // Set ERDP
        self.interrupter.erdp = (@intFromPtr(p) & ~@as(u64, 0b1111)) | (self.interrupter.erdp & @as(u64, 0b1111));
    }
};

/// Entry in ESRT. ESRT is used to define multi-segment Event Rings,
/// which enables runtime expansion and shrinking of the Event Ring.
pub const EventRingSegmentTableEntry = packed struct(u128) {
    /// Base address of the Event Ring Segment.
    ring_segment_base_addr: u64,
    /// Size of the Event Ring Segment.
    size: u16,
    /// Reserved.
    _reserved: u48,
};
