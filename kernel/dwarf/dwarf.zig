const std = @import("std");

const Elf = @import("elf.zig");

test {
    std.testing.refAllDeclsRecursive(@This());
    std.testing.refAllDeclsRecursive(Elf);
}

test "Can read DWARF example program in a test" {
    const bin = @embedFile("dwarf-elf");
    try std.testing.expect(bin.len >= 0x200);
}
