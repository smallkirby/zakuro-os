//! This module provides a serial interface.

const zakuro = @import("zakuro");
const arch = zakuro.arch;

/// Serial console.
pub const Serial = struct {
    const writeFn = *const fn (u8) void;

    /// Pointer to the arch-specific write-function.
    /// Do NOT access this directly, use the `write` function instead.
    _write_fn: writeFn = undefined,

    const Self = @This();

    /// Write a single byte to the serial console.
    pub fn write(self: Self, c: u8) void {
        self._write_fn(c);
    }

    /// Write a string to the serial console.
    pub fn write_string(self: Self, s: []const u8) void {
        for (s) |c| {
            self.write(c);
        }
    }
};

/// Initialize the serial console.
/// You MUST call this function before using the serial console.
pub fn init() Serial {
    var serial = Serial{};
    arch.serial.init_serial(&serial, .COM1, 9600);

    return serial;
}

/// Get the serial console.
/// You MUST call `init` before calling this function.
pub fn get() Serial {
    var serial = Serial{};
    arch.serial.get_serial(&serial, .COM1);

    return serial;
}
