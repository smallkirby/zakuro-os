//! This module provides pretty log using Chameleon.

const std = @import("std");
const Chameleon = @import("chameleon").Chameleon;

pub fn logFunc(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    _ = scope;
    comptime var cham = Chameleon.init(.Auto);
    const ch_debug = comptime cham.bgMagenta().bold();
    const ch_info = comptime cham.bgGreen().bold();
    const ch_warn = comptime cham.bgYellow().bold();
    const ch_err = comptime cham.bgRed().bold();
    const prefix = "[" ++ comptime level.asText() ++ "]";

    const ch = comptime switch (level) {
        .debug => ch_debug,
        .info => ch_info,
        .warn => ch_warn,
        .err => ch_err,
    };

    std.debug.getStderrMutex().lock();
    defer std.debug.getStderrMutex().unlock();
    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.print(ch.fmt(prefix) ++ " " ++ format ++ "\n", args) catch return;
}
