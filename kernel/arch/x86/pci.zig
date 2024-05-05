//! This module provides a x64 impl for PCI access.

const zakuro = @import("zakuro");
const pci = zakuro.pci;
const am = @import("asm.zig");
const ConfigAddress = pci.ConfigAddress;

/// Set PCI configuration address.
pub fn setConfigAddress(addr: ConfigAddress) void {
    am.outl(
        @truncate(addr.as_u32() & 0xFFFF_FFFC),
        pci.addr_configuration_address,
    );
}

/// Get PCI configuration data.
pub fn getConfigData() u32 {
    return am.inl(pci.addr_configuration_data);
}
