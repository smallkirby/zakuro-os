comptime {
    _ = @import("pci.zig");
    _ = @import("main.zig");

    @import("std").testing.refAllDecls(@This());
}
