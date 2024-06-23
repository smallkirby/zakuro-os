const std = @import("std");

/// Initialize ACPI.
pub fn init(rsdp: *Rsdp) void {
    rsdp.valid() catch |e| switch (e) {
        RsdpError.InvalidSignature => @panic("Invalid RSDP signature."),
        RsdpError.InvalidRevision => @panic("Invalid RSDP revision."),
        RsdpError.InvalidChecksum => @panic("Invalid RSDP checksum."),
        RsdpError.InvalidExtendedChecksum => @panic("Invalid RSDP extended checksum."),
    };
}

/// Calculate the checksum of RSDP structure.
/// `checksum` and `extended_checksum` is set so that the sum of all bytes is 0.
fn checksum(data: []u8) u8 {
    var sum: u8 = 0;
    for (data) |byte| {
        sum +%= byte;
    }
    return sum;
}

const RsdpError = error{
    InvalidSignature,
    InvalidRevision,
    InvalidChecksum,
    InvalidExtendedChecksum,
};

/// RSDP (Root System Description Pointer) structure of ACPI v2.0+.
pub const Rsdp = extern struct {
    const size_first_byte = @offsetOf(Rsdp, "length");
    const size_extended_byte = @offsetOf(Rsdp, "_end_marker");

    /// Signature.
    /// It should be "RSD PTR ".
    signature: [8]u8,
    /// Checksum for the first 20 bytes.
    checksum: u8,
    /// OEM ID.
    oem_id: [6]u8,
    /// Revision.
    /// 0 for ACPI 1.0, 2 for ACPI 2.0.
    revision: u8,
    /// RSDT physical address.
    rsdt_address: u32,

    /// Total length of RSDP.
    length: u32,
    /// XSDT (Extended System Descriptor Table) physical address.
    xsdt_address: u64,
    /// Checksum for entire RSDP.
    extended_checksum: u8,
    /// Reserved.
    _reserved: [3]u8,

    _end_marker: void,

    comptime {
        if (size_extended_byte != 36) {
            @compileError("Invalid size of Rsdp.");
        }
    }

    fn valid(self: *Rsdp) !void {
        if (!std.mem.eql(u8, &self.signature, "RSD PTR ")) {
            return RsdpError.InvalidSignature;
        }
        if (self.revision != 2) {
            return RsdpError.InvalidRevision;
        }
        if (checksum(std.mem.asBytes(self)[0..size_first_byte]) != 0) {
            return RsdpError.InvalidChecksum;
        }
        if (checksum(std.mem.asBytes(self)[0..size_extended_byte]) != 0) {
            return RsdpError.InvalidExtendedChecksum;
        }
    }
};
