pub const zakuro = @import("zakuro");

comptime {
    const testing = @import("std").testing;
    testing.refAllDeclsRecursive(zakuro);
}
