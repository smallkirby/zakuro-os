//! This module ensures that submodules are correctly installed.

const std = @import("std");
const ArrayList = std.ArrayList;
const log = std.log;
const plog = @import("plog.zig");
const fs = std.fs;
const exit = std.process.exit;

const EDK2_DIRNAME = "edk2";

pub const std_options = std.Options{
    .log_level = .info, // Edit here to change log level
    .logFn = plog.logFunc,
};

const CommandResult = struct {
    status: u8,
    stdout: []const u8,
    stderr: []const u8,
};

fn change_value(
    line: []const u8,
    key: []const u8,
    value: []const u8,
    allocator: std.mem.Allocator,
) ![]const u8 {
    var splits = std.mem.split(u8, line, "=");
    var ix: usize = 0;

    while (splits.next()) |chunk_| : (ix += 1) {
        const chunk = std.mem.trim(u8, chunk_, " ");
        if (ix == 0 and std.mem.eql(u8, chunk, key)) {
            continue;
        } else if (ix == 0) return line;

        if (ix == 1)
            return try std.fmt.allocPrint(allocator, "{s} = {s}", .{ key, value });
    }

    unreachable;
}

fn modify_target_file(allocator: std.mem.Allocator) !void {
    const edk2_dir = try fs.cwd().openDir(EDK2_DIRNAME, .{});
    const target_file = try edk2_dir.openFile("Conf/target.txt", .{ .mode = .read_write });

    var buf_reader = std.io.bufferedReader(target_file.reader());
    const reader = buf_reader.reader();

    var line = ArrayList(u8).init(allocator);
    defer line.deinit();

    const writer = line.writer();
    var result = ArrayList(u8).init(allocator);
    defer result.deinit();

    const Entry = struct {
        key: []const u8,
        value: []const u8,
    };
    const entries = [_]Entry{
        .{ .key = "TOOL_CHAIN_TAG", .value = "CLANGPDB" },
        .{ .key = "TARGET", .value = "DEBUG" },
        .{ .key = "TARGET_ARCH", .value = "X64" },
        .{ .key = "ACTIVE_PLATFORM", .value = "ZakuroLoaderPkg/ZakuroLoaderPkg.dsc" },
    };

    while (reader.streamUntilDelimiter(writer, '\n', null)) {
        defer line.clearRetainingCapacity();
        var new: []const u8 = line.items;
        for (entries) |ent| {
            new = try change_value(new, ent.key, ent.value, allocator);
        }
        try result.appendSlice(new);
        try result.append('\n');
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => return err,
    }

    try target_file.seekTo(0);
    const new_writer = target_file.writer();
    _ = try new_writer.writeAll(result.items);
}

fn create_symlink(original: []const u8, link: []const u8) !void {
    const edk2_dir = try fs.cwd().openDir(EDK2_DIRNAME, .{});
    try edk2_dir.symLink(original, link, .{ .is_directory = true });
}

fn build_efi() !void {
    const args = [_][]const u8{ "bash", "-c", "source edksetup.sh && build" };
    var child = std.process.Child.init(&args, std.heap.page_allocator);
    child.cwd = EDK2_DIRNAME;
    try child.spawn();
    const term = try child.wait();

    if (term.Exited != 0) {
        return error.MakeFailed;
    }
}

fn source_edksetup(allocator: std.mem.Allocator) !void {
    const args = [_][]const u8{ "bash", "-c", "source edksetup.sh" };
    var child = std.process.Child.init(&args, allocator);
    child.cwd = EDK2_DIRNAME;
    try child.spawn();
    const term = try child.wait();

    if (term.Exited != 0) {
        return error.MakeFailed;
    }
}

fn make_base_tools(allocator: std.mem.Allocator) !void {
    const source_path = try fs.path.join(allocator, &.{
        EDK2_DIRNAME,
        "BaseTools",
        "Source",
        "C",
    });
    const args = [_][]const u8{ "make", "-C", source_path };
    var child = std.process.Child.init(&args, allocator);
    try child.spawn();
    const term = try child.wait();

    if (term.Exited != 0) {
        return error.MakeFailed;
    }
}

pub fn copy_efi() !void {
    const build_dir = try fs.cwd().openDir("edk2/Build/ZakuroLoaderX64/DEBUG_CLANGPDB/X64", .{});
    try build_dir.copyFile("Loader.efi", fs.cwd(), "Loader.efi", .{});
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    fs.cwd().access(EDK2_DIRNAME, .{}) catch {
        log.err("Cannot access EDK2 directory...", .{});
        exit(1);
    };

    const edk2_loader_path = try fs.path.join(allocator, &.{
        EDK2_DIRNAME,
        "ZakuroLoaderPkg",
    });
    fs.cwd().access(edk2_loader_path, .{}) catch {
        log.info("Creating symlink to our loader package in EDK2 directory...", .{});
        create_symlink("../ZakuroLoaderPkg", "ZakuroLoaderPkg") catch |err| {
            log.err("Failed to create symlink to our loader package in EDK2 directory.", .{});
            log.err("{?}", .{err});
            exit(1);
        };
    };

    log.info("Building BaseTools.", .{});
    make_base_tools(allocator) catch {
        log.err("Failed to build BaseTools.", .{});
        exit(1);
    };

    log.info("Sourcing edksetup.sh.", .{});
    source_edksetup(allocator) catch {
        log.err("Failed to source edksetup.sh.", .{});
        exit(1);
    };

    log.info("Modifying target.txt.", .{});
    modify_target_file(allocator) catch |err| {
        log.err("Failed to modify target.txt.", .{});
        log.err("{?}", .{err});
        exit(1);
    };

    log.info("Building EFI.", .{});
    build_efi() catch {
        log.err("Failed to build EFI.", .{});
        exit(1);
    };

    log.info("Copying EFI to the project root.", .{});
    copy_efi() catch {
        log.err("Failed to copy EFI.", .{});
        exit(1);
    };

    log.info("Finished building EFI.", .{});
}
