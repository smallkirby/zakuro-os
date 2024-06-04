//! This module defines a UEFI memory map structures.

const std = @import("std");

/// Thin wrapper struct for memory map passed to by the bootloader.
/// The memory map is an array of memory descriptors.
/// The size of each descriptor is given by `descriptor_size`.
/// For the detail, refer to Section 7.2.3 of the UEFI Specification v2.10.
pub const MemoryMap = extern struct {
    /// Size of the buffer allocated for this memory map.
    buffer_size: usize,
    /// Pointer to the array of EFI_MEMORY_DESCRIPTORs.
    descriptors: [*]u8,
    /// Actual size of this memory map.
    map_size: usize,
    /// Uniqueue identifier for the memory map.
    /// This field is used to check if the map is up-to-date.
    map_key: u64,
    /// Size of each descriptor in bytes.
    descriptor_size: usize,
    /// The version of the EFI_MEMORY_DESCRIPTOR.
    descriptor_version: u32,

    /// Given the current memory descriptor, return the next one.
    pub fn next(self: *MemoryMap, current_desc: ?*MemoryDescriptor) ?*MemoryDescriptor {
        if (current_desc) |desc| {
            const ret: usize = @intFromPtr(desc) + self.descriptor_size;
            return if (ret < @intFromPtr(self.descriptors) + self.map_size)
                @ptrFromInt(ret)
            else
                null;
        } else {
            return @alignCast(@ptrCast(self.descriptors));
        }
    }
};

/// EFI_MEMORY_DESCRIPTOR.
/// This struct describes a region of memory.
pub const MemoryDescriptor = extern struct {
    /// Type of the memory region.
    typ: EfiMemoryType,
    /// Physical address of the start of the memory region.
    physical_start: u64,
    /// Virtual address of the start of the memory region.
    virtual_start: u64,
    /// Number of pages in this memory region.
    num_pages: usize,
    /// Bit mask of capabilities for this memory region.
    /// Note that it does not necessarily represent the current state of the memory region.
    attr: u64,
};

/// EFI memory types.
pub const EfiMemoryType = enum(u32) {
    /// Not usable.
    ReservedMemoryType,
    /// Code of the loaded UEFI app (bootloader).
    LoaderCode,
    /// Data of the loaded UEFI app (bootloader) and memory pool.
    LoaderData,
    /// Code of UEFI Boot Service Driver.
    BootServicesCode,
    /// Data of UEFI Boot Service Driver.
    BootServicesData,
    RuntimeServicesCode,
    RuntimeServicesData,
    /// Memory available for general use.
    ConventionalMemory,
    /// Memory that contains errors.
    UnusableMemory,
    ACPIReclaimMemory,
    ACPIMemoryNVS,
    MemoryMappedIO,
    MemoryMappedIOPortSpace,
    PalCode,
    PersistentMemory,
    UnacceptedMemoryType,
    MaxMemoryType,

    /// Check if the memory type is available for general use by OS.
    pub fn isAvailable(self: EfiMemoryType) bool {
        return switch (self) {
            .BootServicesCode,
            .BootServicesData,
            .ConventionalMemory,
            => true,
            else => false,
        };
    }
};

const testing = std.testing;

test "descriptor next" {
    // Note that the array of MemoryDescriptor can insert padding between each element,
    // although UEFI does not.
    var descs = [_]MemoryDescriptor{
        .{ .typ = .ConventionalMemory, .physical_start = 0, .virtual_start = 0, .num_pages = 0, .attr = 0 },
        .{ .typ = .ConventionalMemory, .physical_start = 1, .virtual_start = 0, .num_pages = 0, .attr = 0 },
        .{ .typ = .ConventionalMemory, .physical_start = 2, .virtual_start = 0, .num_pages = 0, .attr = 0 },
    };
    var map = MemoryMap{
        .buffer_size = 0x100,
        .descriptors = @ptrCast(&descs),
        .map_size = 0x30 * 3,
        .map_key = 0,
        .descriptor_size = 0x30,
        .descriptor_version = 1,
    };
    const map_ptr = &map;

    var current_desc = map_ptr.next(null);
    try testing.expectEqual(&descs[0], current_desc);
    current_desc = map_ptr.next(current_desc);
    try testing.expectEqual(0x30, @intFromPtr(current_desc) - @intFromPtr(&descs[0]));
    current_desc = map_ptr.next(current_desc);
    try testing.expectEqual(null, map_ptr.next(current_desc));
}
