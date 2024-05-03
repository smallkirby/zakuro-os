//! This module provides a logging to the serial console.

const Serial = @import("serial.zig").Serial;
const std = @import("std");
const stdlog = std.log;
const io = std.io;
const format = std.fmt.format;

var serial: Serial = undefined;

const LogError = error{};
const Writer = std.io.Writer(
    void,
    LogError,
    writer_function,
);

/// Initialize the logger with the given serial console.
/// You MUST call this function before using the logger.
pub fn init(ser: Serial) void {
    serial = ser;
}

fn writer_function(context: void, bytes: []const u8) LogError!usize {
    _ = context;
    serial.write_string(bytes);

    return bytes.len;
}

fn log(comptime level: stdlog.Level, comptime fmt: []const u8, args: anytype) void {
    const level_str = comptime switch (level) {
        .debug => "[DEBUG] ",
        .info => "[INFO ] ",
        .warn => "[WARN ] ",
        .err => "[ERROR] ",
    };
    format(
        Writer{ .context = {} },
        level_str ++ fmt ++ "\n",
        args,
    ) catch unreachable;
}

pub fn debug(comptime fmt: []const u8, args: anytype) void {
    log(stdlog.Level.debug, fmt, args);
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    log(stdlog.Level.info, fmt, args);
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    log(stdlog.Level.warn, fmt, args);
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    @setCold(true);
    log(stdlog.Level.err, fmt, args);
}
