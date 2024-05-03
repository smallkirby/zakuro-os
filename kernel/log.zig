//! This module provides a logging to the serial console.

const Serial = @import("serial.zig").Serial;
const stdlog = @import("std").log;

var serial: Serial = undefined;

/// Initialize the logger with the given serial console.
/// You MUST call this function before using the logger.
pub fn init(ser: Serial) void {
    serial = ser;
}

pub fn log(level: stdlog.Level, message: []const u8) void {
    _ = level;
    serial.write_string(message);
}

pub fn debug(message: []const u8) void {
    log(stdlog.Level.debug, message);
}

pub fn info(message: []const u8) void {
    log(stdlog.Level.info, message);
}

pub fn warn(message: []const u8) void {
    log(stdlog.Level.warn, message);
}

pub fn err(message: []const u8) void {
    log(stdlog.Level.err, message);
}
