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

pub const default_log_options = std.Options{
    .log_level = .debug,
    .logFn = log,
};

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

fn log(
    comptime level: stdlog.Level,
    scope: @Type(.EnumLiteral),
    comptime fmt: []const u8,
    args: anytype,
) void {
    const level_str = comptime switch (level) {
        .debug => "[DEBUG] ",
        .info => "[INFO ] ",
        .warn => "[WARN ] ",
        .err => "[ERROR] ",
    };
    const scope_str = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    format(
        Writer{ .context = {} },
        level_str ++ scope_str ++ fmt ++ "\n",
        args,
    ) catch unreachable;
}
