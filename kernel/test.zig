pub const zakuro = @import("zakuro");

test {
    const testing = @import("std").testing;
    testing.refAllDeclsRecursive(zakuro);
}
