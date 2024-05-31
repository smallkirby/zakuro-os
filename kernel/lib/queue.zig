//! Queue data structure.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Error = error{
    /// Failed to allocate memory.
    OutOfMemory,
    /// The queue is full.
    QueueFull,
};

/// Fixed sized queue data structure.
/// The queue is not extended when it is full.
pub fn FixedSizeQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Max length of the queue.
        capacity: usize,
        /// Underlying data.
        data: []T,
        /// Memory allocator.
        /// An allocator is used only to allocate the underlying data at initialization.
        /// This field is stored just to deinit it.
        allocator: Allocator,

        /// Index of the next element to be read.
        pos_read: usize = 0,
        /// Index of the next element to be written.
        pos_write: usize = 0,
        /// Length of the elements in the queue.
        len: usize = 0,

        /// Initiate the queue.
        /// Caller MUST call `deinit()`.
        pub fn init(n: usize, allocator: Allocator) Allocator.Error!Self {
            const data = try allocator.alloc(T, n);

            return Self{
                .capacity = n,
                .data = data,
                .allocator = allocator,
            };
        }

        /// Free the underlying data to deinitalize the queue.
        pub fn deinit(self: *Self) void {
            self.allocator.free(self.data);
        }

        /// Get the front element of the queue.
        pub fn front(self: *Self) ?T {
            return if (self.len == 0)
                null
            else
                self.data[self.pos_read];
        }

        /// Get the front element of the queue and remove it.
        pub fn pop(self: *Self) ?T {
            const ret = if (self.len == 0)
                null
            else
                self.data[self.pos_read];

            if (ret != null) {
                self.pos_read = (self.pos_read + 1) % self.capacity;
                self.len -= 1;
            }

            return ret;
        }

        /// Push an element to the back of the queue.
        pub fn push(self: *Self, elem: T) Error!void {
            if (self.len == self.capacity) {
                return Error.QueueFull;
            }

            self.data[self.pos_write] = elem;
            self.pos_write = (self.pos_write + 1) % self.capacity;
            self.len += 1;
        }
    };
}

const testing = std.testing;

test "Length, Pop, Push" {
    const Queue = FixedSizeQueue(u32);
    var q = try Queue.init(5, testing.allocator);
    defer q.deinit();
    try testing.expectEqual(0, q.len);

    // Simple count
    try q.push(1);
    try q.push(2);
    try q.push(3);
    try testing.expectEqual(3, q.len);
    try q.push(4);
    try q.push(5);
    try testing.expectEqual(5, q.len);

    // pos_write < pos_read
    try testing.expectEqual(1, q.pop());
    try testing.expectEqual(2, q.pop());
    try testing.expectEqual(3, q.pop());
    try testing.expectEqual(2, q.len);

    try q.push(6);
    try q.push(7); // w=2, r=3
    try testing.expectEqual(4, q.len);
}

test "Error Full" {
    const Queue = FixedSizeQueue(u64);
    var q = try Queue.init(3, testing.allocator);
    defer q.deinit();
    for (0..3) |i| {
        try q.push(i);
    }

    try testing.expectError(Error.QueueFull, q.push(4));
}

test "Empty pop" {
    const Queue = FixedSizeQueue(u64);
    var q = try Queue.init(3, testing.allocator);
    defer q.deinit();
    try testing.expectEqual(null, q.pop());
}

test "Front" {
    const Queue = FixedSizeQueue(u64);
    var q = try Queue.init(3, testing.allocator);
    defer q.deinit();
    try testing.expectEqual(null, q.front());

    try q.push(1);
    try testing.expectEqual(1, q.front());
    try q.push(2);
    try testing.expectEqual(1, q.front());
    _ = q.pop();
    try testing.expectEqual(2, q.front());
    try testing.expectEqual(1, q.len);
}
