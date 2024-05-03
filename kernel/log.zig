//! This module provides a logging to the serial console.

const Serial = @import("serial.zig").Serial;
const stdlog = @import("std").log;

var serial: Serial = undefined;

/// Initialize the logger with the given serial console.
/// You MUST call this function before using the logger.
pub fn init(ser: Serial) void {
    serial = ser;
}

fn log(comptime level: stdlog.Level, message: []const u8) void {
    const level_str = comptime switch (level) {
        .debug => "[DEBUG] ",
        .info => "[INFO ] ",
        .warn => "[WARN ] ",
        .err => "[ERROR] ",
    };
    serial.write_string(level_str);
    serial.write_string(message);
    serial.write_string("\n");
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
    @setCold(true);
    log(stdlog.Level.err, message);
}
