//! This module ensures that submodules are correctly installed.

const std = @import("std");
const ArrayList = std.ArrayList;
const log = std.log;
const Chameleon = @import("chameleon").Chameleon;

const EDK2_DIRNAME = "edk2";

pub const std_options = std.Options{
    .log_level = .info, // Edit here to change log level
    .logFn = logFunc,
};

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

const CommandResult = struct {
    status: u8,
    stdout: []const u8,
    stderr: []const u8,
};

fn init_submodule(allocator: std.mem.Allocator) !CommandResult {
    // exec `git submodule update --init --recursive`
    const args = [_][]const u8{
        "git", "submodule", "update", "--init", "--recursive",
    };
    var child = std.process.Child.init(&args, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    var stdout = ArrayList(u8).init(allocator);
    var stderr = ArrayList(u8).init(allocator);
    defer {
        stdout.deinit();
        stderr.deinit();
    }

    try child.spawn();
    child.collectOutput(&stdout, &stderr, 1024) catch |err| switch (err) {
        error.StdoutStreamTooLong => {},
        else => {
            log.err("Failed to collect output: {}", .{err});
        },
    };
    const term = try child.wait();

    return CommandResult{
        .status = term.Exited,
        .stdout = &.{},
        .stderr = try stderr.toOwnedSlice(),
    };
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    std.fs.cwd().access(EDK2_DIRNAME, .{}) catch {
        log.info("Submodule EDK2 not found, initializing...", .{});
        _ = try init_submodule(allocator);
        log.info("Submodule EDK2 initialized.", .{});
    };

    log.info("Submodule EDK2 is conformed installed.", .{});
}
