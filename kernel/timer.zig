const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const zakuro = @import("zakuro");
const arch = zakuro.arch;
const event = zakuro.event;

/// Total tick count.
var total_tick: u64 = 0;
var timers: ArrayList(Timer) = undefined;

/// Initialize a Local APIC timer.
pub fn init(vector: u8, allocator: Allocator, rsdp: *arch.Rsdp) void {
    total_tick = 0;
    timers = ArrayList(Timer).init(allocator);
    arch.timer.init(vector, rsdp);
}

/// Initiate an new timer with the given timeout.
pub fn newTimer(timeout: u64, id: u64) !void {
    try timers.append(Timer.new(timeout, id));
}

/// Increment the tick count by one.
/// If there is a timer that has reached the timeout,
/// interrupt message is pushed to the message queue.
pub fn tick() void {
    total_tick += 1;

    var i: usize = 0;
    while (i < timers.items.len) {
        const timer = timers.items[i];
        if (timer.timeout <= total_tick) {
            event.push(.{ .timer = timers.orderedRemove(i) }) catch @panic("Failed to push timer message");
        } else {
            i += 1;
        }
    }
}

/// Get the total tick count.
pub fn getTicks() u64 {
    return total_tick;
}

pub const Timer = struct {
    /// Timeout in ticks.
    timeout: u64,
    /// Timer ID.
    id: u64,

    pub fn new(timeout: u64, id: u64) Timer {
        return Timer{
            .timeout = timeout,
            .id = id,
        };
    }
};

/// Event message sent when a timer reaches the timeout.
pub const TimerMessage = Timer;
