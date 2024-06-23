//! Eevnt is a enqueued message that is expected to be processed in the main loop lazily.
//! The main purpose of events is to decouple the interrupt handler and the main loop.
//! In interrupt handlers, an event message is generated an enqueued,
//! algouth the message is not processed immediately resulting in a smaller cost of interrupt handling.

const std = @import("std");
const Allocator = std.mem.Allocator;

const zakuro = @import("zakuro");
const FixedSizeQueue = zakuro.lib.queue.FixedSizeQueue;

const EventQueue = FixedSizeQueue(EventMessage);

/// Event queue instance.
var queue: EventQueue = undefined;

/// Initialize the event queue instance with the given capacity.
pub fn init(capacity: usize, allocator: Allocator) !void {
    queue = try EventQueue.init(capacity, allocator);
}

/// Size of the enqueued event messages.
pub fn size() usize {
    return queue.len;
}

/// Push the event message to the queue.
pub fn push(event: EventMessage) !void {
    try queue.push(event);
}

/// Pop the event message from the queue.
pub fn pop() ?EventMessage {
    return queue.pop();
}

const EventMessageType = enum {
    mouse,
    timer,
};

/// Event message.
/// The message is enqueued in the interrupt handler and processed in the main loop.
pub const EventMessage = union(EventMessageType) {
    mouse: void,
    timer: zakuro.timer.TimerMessage,
};
