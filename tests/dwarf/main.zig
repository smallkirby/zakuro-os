const std = @import("std");

pub fn fibo(n: u32) u32 {
    if (n <= 1) {
        return n;
    }
    return fibo(n - 1) + fibo(n - 2);
}

pub fn main() !void {
    const result = fibo(10);
    std.log.debug("fibo(10) = {d}\n", .{result});
}
