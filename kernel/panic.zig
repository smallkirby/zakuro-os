//! This module provides a panic implementation.
//! Zig has panic impletentations for each target platform.
//! However, the impl for .freestanding is just a @breakpoint.
//! Therefore, we implement a simple panic handler here.

const std = @import("std");
const zakuro = @import("zakuro");
const builtin = std.builtin;
const debug = std.debug;
const log = std.log.scoped(.panic);
const ser = zakuro.serial;
const format = std.fmt.format;

/// Implementation of the panic function.
pub const panic_fn = panic;

var serial: ser.Serial = undefined;
const PanicError = error{};
const Writer = std.io.Writer(
    void,
    PanicError,
    writerFunction,
);

fn write(comptime fmt: []const u8, args: anytype) void {
    format(
        Writer{ .context = {} },
        fmt,
        args,
    ) catch unreachable;
}

fn writerFunction(context: void, bytes: []const u8) PanicError!usize {
    _ = context;
    serial.write_string(bytes);

    return bytes.len;
}

fn panic(
    msg: []const u8,
    error_return_trace: ?*builtin.StackTrace,
    ret_addr: ?usize,
) noreturn {
    @setCold(true);
    _ = ret_addr;

    serial = ser.get();
    log.err("{s}", .{msg});

    if (error_return_trace) |ert| {
        printStackTrace(ert) catch |err| {
            log.err("Failed to write stack trace: {s}\n", .{err});
        };
    } else {
        log.err("RA: 0x{X}", .{@returnAddress()});
    }

    bpHalt();
}

fn bpHalt() noreturn {
    @setCold(true);
    while (true) {
        @breakpoint();
    }
}

fn printStackTrace(stack_trace: *builtin.StackTrace) !void {
    var frames_left: usize = @min(stack_trace.index, stack_trace.instruction_addresses.len);
    var frames_index: usize = 0;

    while (frames_left != 0) : ({
        frames_left -= 1;
        frames_index = (frames_index + 1) % stack_trace.instruction_addresses.len;
    }) {
        const return_address = stack_trace.instruction_addresses[frames_index];
        printFrame(return_address) catch |err| write("Failed to print this frame: {s}\n", .{err});
    }
}

fn printFrame(address: usize) !void {
    write("{x}: {s}\n", .{ address, "TODO: print frame" });
}
