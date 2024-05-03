//! This module provides a panic implementation.
//! Zig has panic impletentations for each target platform.
//! However, the impl for .freestanding is just a @breakpoint.
//! Therefore, we implement a simple panic handler here.

const builtin = @import("std").builtin;
const log = @import("log.zig");

/// Implementation of the panic function.
pub const panic_fn = panic;

fn panic(
    msg: []const u8,
    error_return_trace: ?*builtin.StackTrace,
    ret_addr: ?usize,
) noreturn {
    @setCold(true);
    _ = error_return_trace;
    _ = ret_addr;

    log.err("!!!!!!!!!!!!!");
    log.err("!!! PANIC !!!");
    log.err("!!!!!!!!!!!!!");
    log.err(msg);
    log.err("");

    while (true) {
        @breakpoint();
    }
}
