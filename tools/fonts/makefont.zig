//! This tool generates a binary data of ASCII fonts.
//! First, it reads a text file containing ASCII font data.
//! Then it compiles the data into a binary file named `fontdata`.
//! Finally, it converts the binary file into an ELF file using `objcopy`.
//! The symbol name of the binary data is `_binary_fontdata_**`,
//! where `**` is either of `start`, `end`, or `size`.

const std = @import("std");
const os = std.os;
const fs = std.fs;
const clap = @import("clap");
const ArrayList = std.ArrayList;
const plog = @import("plog");
const log = std.log;

pub const std_options = std.Options{
    .log_level = .info, // Edit here to change log level
    .logFn = plog.logFunc,
};

/// Parse a 1x8 ASCII font line into a byte.
fn compile_line(line: []const u8) u8 {
    if (line.len != 8) {
        log.err("Invalid line length: {d}: {s}\n", .{ line.len, line });
        @panic("Invalid line length");
    }

    var result: u8 = 0;

    for (line, 0..) |c, i| {
        switch (c) {
            '.' => {},
            '@' => result |= @as(u8, 1) << @truncate(7 - i),
            else => {
                log.err("Invalid character: '{c}': {s}", .{ c, line });
                @panic("Invalid character");
            },
        }
    }

    return result;
}

/// Compile a text file containing ASCII font data into a binary data.
fn compile(allocator: std.mem.Allocator, in_path: []const u8) ![]u8 {
    const file = try fs.cwd().openFile(in_path, .{});
    defer file.close();
    var result = ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var buf_reader = std.io.bufferedReader(file.reader());
    const reader = &buf_reader.reader();

    var line = std.ArrayList(u8).init(allocator);
    defer line.deinit();

    const writer = line.writer();
    while (reader.streamUntilDelimiter(writer, '\n', null)) {
        defer line.clearRetainingCapacity();
        if (line.items.len == 8 and (line.items[0] == '.' or line.items[0] == '@')) {
            const d = compile_line(line.items);
            try result.append(d);
        }
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => return err,
    }

    return result.toOwnedSlice();
}

/// Output a binary data to a file.
fn output2file(path: []const u8, data: []u8) !void {
    const file = try fs.cwd().createFile(path, .{});
    const writer = file.writer();
    _ = try writer.writeAll(data);
}

// TODO: Zig's drop-in objcopy is insufficient?
/// Convert a binary file into an ELF file using `objcopy` command.
fn objcopy(in_path: []const u8, out_path: []const u8, allocator: std.mem.Allocator) !void {
    const in_path_abs = try fs.cwd().realpathAlloc(allocator, in_path);
    const out_path_abs = try fs.path.resolve(allocator, &.{out_path});
    const in_path_dir = fs.path.dirname(in_path_abs).?;
    const in_filename = fs.path.basename(in_path_abs);
    defer {
        allocator.free(in_path_abs);
        allocator.free(out_path_abs);
    }

    const args = [_][]const u8{
        "objcopy",
        "-I",
        "binary",
        "-O",
        "elf64-x86-64",
        "-B",
        "i386:x86-64",
        in_filename,
        out_path_abs,
    };
    var child = std.process.Child.init(&args, allocator);
    child.cwd = in_path_dir;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    var stdout = ArrayList(u8).init(allocator);
    var stderr = ArrayList(u8).init(allocator);
    errdefer {
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

    if (term.Exited != 0) {
        return error.ObjcopyFailed;
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\-o, --output <str>     Output file path.
        \\-i, --input  <str>       Input font file path.
        \\
    );
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    }

    // check if the output and input file paths are specified
    var out_path: []const u8 = undefined;
    var in_path: []const u8 = undefined;
    if (res.args.output) |output| {
        out_path = output;
    } else {
        log.err("Output file path is not specified.", .{});
        std.process.exit(1);
    }
    if (res.args.input) |input| {
        in_path = input;
    } else {
        log.err("Input font file path is not specified.", .{});
        std.process.exit(1);
    }

    log.info("Compiling font data from {s} to {s}", .{ in_path, out_path });
    const bin = try compile(allocator, in_path);
    defer allocator.free(bin);
    const tmp_out_path = "fontdata";

    log.info("Outputting font data to {s}", .{tmp_out_path});
    try output2file(tmp_out_path, bin);

    log.info("Converting binary data to ELF file {s}", .{out_path});
    try objcopy(tmp_out_path, out_path, allocator);
}
