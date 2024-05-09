//! This file provides a MMIO Registers that have restrictions on the access size.

const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const log = std.log.scoped(.mmio);

/// Restrictions on the register access size.
pub const AccessWidth = enum(u8) {
    QWORD = 8,
    DWORD = 4,
    WORD = 2,
    BYTE = 1,

    pub fn utype(comptime self: AccessWidth) type {
        return switch (self) {
            .QWORD => u64,
            .DWORD => u32,
            .WORD => u16,
            .BYTE => u8,
        };
    }

    pub fn size(comptime self: AccessWidth) usize {
        return @sizeOf(self.utype());
    }
};

/// MMIO-register with restrictions on the access size.
pub fn Register(
    comptime T: type,
    comptime access_width: AccessWidth,
) type {
    comptime {
        assert(@sizeOf(T) % access_width.size() == 0);
    }

    return packed struct {
        const Self = @This();
        /// Number of bytes in which the register is accessed.
        const asize = access_width.size();
        /// Representive type for the access width.
        const atype = access_width.utype();
        /// Number of access width elements in the register.
        const len = @sizeOf(T) / asize;

        /// Underlying data
        _data: T,

        /// Read the data from the underlying register with the correct access width.
        pub fn read(self: *volatile Self) T {
            var ret: T = mem.zeroes(T);
            const ret_bytes: [*]volatile atype = @ptrCast(mem.asBytes(&ret));
            const val: [*]volatile atype = @ptrCast(mem.asBytes(&self._data));
            for (0..len) |i| {
                ret_bytes[i] = val[i];
            }

            return ret;
        }

        /// Write the data to the underlying register with the correct access width.
        pub fn write(self: *volatile Self, value: T) void {
            const bytes: [*]const volatile atype = @ptrCast(mem.asBytes(&value));
            const val: [*]volatile atype = @ptrCast(mem.asBytes(&self._data));
            for (0..len) |i| {
                val[i] = bytes[i];
            }
        }

        /// Modify the part of the fields of the register with the given value.
        pub fn modify(self: *volatile Self, value: anytype) void {
            var new = self.read();
            const info = @typeInfo(@TypeOf(value));
            inline for (info.Struct.fields) |field| {
                @field(new, field.name) = @field(value, field.name);
            }

            self.write(new);
        }
    };
}

//////////////////////////////////

const testing = std.testing;

test "Test Register size and operations" {
    const A = packed struct(u32) {
        a: u16,
        b: u16,
    };

    const RA = Register(A, .DWORD);
    try testing.expectEqual(@bitSizeOf(RA), @bitSizeOf(A));

    var a = A{ .a = 0x1234, .b = 0x5678 };
    const ptr: *volatile RA = @ptrCast(&a);

    try testing.expectEqual(ptr.read(), a);
    a.b = 0xDEAD;
    try testing.expectEqual(ptr.read(), a);

    ptr.write(A{ .a = 0x5678, .b = 0x1234 });
    try testing.expectEqual(a, A{ .a = 0x5678, .b = 0x1234 });
    try testing.expectEqual(ptr.read(), a);

    ptr.modify(.{ .b = 0xBEEF });
    try testing.expectEqual(a, A{ .a = 0x5678, .b = 0xBEEF });
    try testing.expectEqual(ptr.read(), a);
}
