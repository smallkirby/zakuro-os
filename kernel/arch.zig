//! Thin wrapper to access arch-specific modules.
//! Now, Zakuro-OS supports only x86_64 architecture.

pub const impl = @import("arch/x86/arch.zig");
