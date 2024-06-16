//! This module provides a logging to the serial console.

const std = @import("std");
const format = std.fmt.format;
const option = @import("option");
const stdlog = std.log;
const io = std.io;

const zakuro = @import("zakuro");
const Serial = zakuro.serial.Serial;
const Console = zakuro.console.Console;

const Chameleon = @import("chameleon").Chameleon;

var serial: Serial = undefined;
var console: ?*Console = null;

const LogError = error{
    /// Logging to the graphical console failed.
    ConsoleError,
};
const Writer = std.io.Writer(
    void,
    LogError,
    writer_function,
);

pub const default_log_options = std.Options{
    .log_level = switch (option.log_level) {
        .debug => .debug,
        .info => .info,
        .warn => .warn,
        .err => .err,
    },
    .logFn = log,
};

/// Initialize the logger with the given serial console.
/// You MUST call this function before using the logger.
pub fn init(ser: Serial) void {
    serial = ser;
}

/// Set the graphical console.
/// After calling this function, the logger will use both the serial console and the graphical console.
pub fn setConsole(con: *Console) void {
    console = con;
}

/// Unset the graphical console.
pub fn unsetConsole() ?*Console {
    const tmp = console;
    console = null;
    return tmp;
}

fn writer_function(_: void, bytes: []const u8) LogError!usize {
    serial.write_string(bytes);
    if (console) |con| {
        _ = Console.write(.{ .console = con }, bytes) catch return LogError.ConsoleError;
    }

    return bytes.len;
}

fn log(
    comptime level: stdlog.Level,
    scope: @Type(.EnumLiteral),
    comptime fmt: []const u8,
    args: anytype,
) void {
    const level_str = comptime switch (level) {
        .debug => "[DEBUG]",
        .info => "[INFO ]",
        .warn => "[WARN ]",
        .err => "[ERROR]",
    };
    const scope_str = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";

    if (option.prettylog) {
        comptime var cham = Chameleon.init(.Auto);
        const chameleon = switch (level) {
            .debug => cham.bgGray().bold(),
            .info => cham.bgBlue().bold(),
            .warn => cham.bgYellow().bold(),
            .err => cham.bgRed().bold(),
        };
        format(
            Writer{ .context = {} },
            chameleon.fmt(level_str) ++ " " ++ scope_str ++ fmt ++ "\n",
            args,
        ) catch unreachable;
    } else {
        format(
            Writer{ .context = {} },
            level_str ++ " " ++ scope_str ++ fmt ++ "\n",
            args,
        ) catch unreachable;
    }
}
