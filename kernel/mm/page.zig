//! Defines page frame related types.
//! For now, we support flat memory model,
//! wehere the PFN of the page can be calculated just by dividing the physical address of the page by the page size.

const std = @import("std");

const zakuro = @import("zakuro");
const arch = zakuro.arch;

/// Page Frame Number.
/// The page frame refers to the physical memory region.
pub const Pfn = usize;
/// Page size in bytes.
const page_size = arch.page_size;

/// Converts the physical address to the page frame number in the flat model.
/// NOTE: This function assumes that the physical address is aligned to the page size.
pub inline fn phys2pfn(phys: u64) Pfn {
    return phys / page_size;
}

/// Converts the page frame number to the physical address in the flat model.
pub inline fn pfn2phys(pfn: Pfn) u64 {
    return pfn * page_size;
}
