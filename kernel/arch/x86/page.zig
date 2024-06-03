const std = @import("std");
const log = std.log.scoped(.archp);
const Allocator = std.mem.Allocator;

const arch = @import("arch.zig");
const am = @import("asm.zig");

const page_size_4k: usize = arch.page_size;
const page_size_2mb: usize = page_size_4k << 9;
const page_size_1gb: usize = page_size_2mb << 9;
const page_shift = arch.page_shift;
const num_table_entries: usize = 512;

/// 1st level page table.
/// TODO: Do not statically allocate these.
/// TODO: Do not do identity mapping.
var pml4_table: [num_table_entries]Pml4Entry align(page_size_4k) = [_]Pml4Entry{
    Pml4Entry.new_nopresent(),
} ** num_table_entries;
/// 2nd level page table.
var pdp_table: [num_table_entries]PdptEntry align(page_size_4k) = [_]PdptEntry{
    PdptEntry.new_nopresent(),
} ** num_table_entries;

const PageDirectory = [num_table_entries]PdtEntry;
/// 3rd level page table.
/// TODO: For now, we use identity mapping only. So we only need 3 levels of page tables.
///     In the identity mapping, each page table entry maps 1GiB of memory.
var page_direcotry: [64]PageDirectory align(page_size_4k) = [_]PageDirectory{
    [_]PdtEntry{
        PdtEntry.new_nopresent(),
    } ** num_table_entries,
} ** 64;

/// Construct the identity mapping and switch to it.
/// This function uses 2MiB pages to reduce the number of page table entries.
/// Only the first entry of the PML4 table is used.
/// TODO: This is a temporary implementation. Replace it.
pub fn initIdentityMapping() void {
    // Construct PML4 table.
    pml4_table[0] = Pml4Entry.new(&pdp_table[0]);

    // Construct PDPT table and 2MiB PDT entries.
    for (0..64) |i| {
        pdp_table[i] = PdptEntry.new(@intFromPtr(&page_direcotry[i]));

        for (0..512) |j| {
            page_direcotry[i][j] = PdtEntry.new_4mb(
                i * page_size_1gb + j * page_size_2mb,
            );
        }
    }

    // Load CR3 register.
    am.loadCr3(@intFromPtr(&pml4_table[0]));
}

/// Show the process of the address translation for the given linear address.
/// TODO: do not use logger of this scope.
pub fn showPageTable(lin_addr: u64) void {
    // TODO: remove magic numbers.
    const pml4_index = (lin_addr >> 39) & 0x1FF;
    const pdp_index = (lin_addr >> 30) & 0x1FF;
    const pdt_index = (lin_addr >> 21) & 0x1FF;
    const pt_index = (lin_addr >> 12) & 0x1FF;
    log.err("Linear Address: 0x{X:0>16} (0x{X}, 0x{X}, 0x{X}, 0x{X})", .{
        lin_addr,
        pml4_index,
        pdp_index,
        pdt_index,
        pt_index,
    });

    const cr3 = am.readCr3();
    const pml4: [*]Pml4Entry = @ptrFromInt(cr3);
    log.debug("PML4: 0x{X:0>16}", .{@intFromPtr(pml4)});
    const pml4_entry = pml4[pml4_index];
    log.debug("\tPML4[{d}]: 0x{X:0>16}", .{ pml4_index, std.mem.bytesAsValue(u64, &pml4_entry).* });
    const pdp: [*]PdptEntry = @ptrFromInt(pml4_entry.phys_pdpt << page_shift);
    log.debug("PDPT: 0x{X:0>16}", .{@intFromPtr(pdp)});
    const pdp_entry = pdp[pdp_index];
    log.debug("\tPDPT[{d}]: 0x{X:0>16}", .{ pdp_index, std.mem.bytesAsValue(u64, &pdp_entry).* });
    const pdt: [*]PdtEntry = @ptrFromInt(pdp_entry.phys_pdt << page_shift);
    log.debug("PDT: 0x{X:0>16}", .{@intFromPtr(pdt)});
    const pdt_entry = pdt[pdt_index];
    log.debug("\tPDT[{d}]: 0x{X:0>16}", .{ pdt_index, std.mem.bytesAsValue(u64, &pdt_entry).* });
}

/// PML4E
const Pml4Entry = packed struct(u64) {
    /// Present.
    present: bool = true,
    /// Read/Write.
    /// If set to false, wirte access is not allowed to the 512GB region.
    rw: bool,
    /// User/Supervisor.
    /// If set to false, user-mode access is not allowed to the 512GB region.
    us: bool,
    /// Page-level writh-through.
    /// Indirectly determines the memory type used to access the PDP Table.
    pwt: bool = false,
    /// Page-level cache disable.
    /// Indirectly determines the memory type used to access the PDP Table.
    pcd: bool = false,
    /// Accessed.
    /// Indicates wheter this entry has been used for translation.
    accessed: bool = false,
    /// Ignored.
    _ignored1: u1 = 0,
    /// ReservedZ.
    _reserved1: u1 = 0,
    /// Ignored
    _ignored2: u3 = 0,
    /// Ignored except for HLAT paging.
    restart: bool = false,
    /// 4KB aligned address of the PDP Table.
    phys_pdpt: u52,

    /// Get a new PML4E entry with the present bit set to false.
    pub fn new_nopresent() Pml4Entry {
        return Pml4Entry{
            .present = false,
            .rw = false,
            .us = false,
            .phys_pdpt = 0,
        };
    }

    /// Get a new PML4E entry.
    pub fn new(phys_pdpt: *PdptEntry) Pml4Entry {
        return Pml4Entry{
            .present = true,
            .rw = true,
            .us = false,
            .phys_pdpt = @truncate(@as(u64, @intFromPtr(phys_pdpt)) >> page_shift),
        };
    }
};

/// PDPT Entry
const PdptEntry = packed struct(u64) {
    /// Present.
    present: bool = true,
    /// Read/Write.
    /// If set to false, wirte access is not allowed to the 1GiB region.
    rw: bool,
    /// User/Supervisor.
    /// If set to false, user-mode access is not allowed to the GiB region.
    us: bool,
    /// Page-level writh-through.
    /// Indirectly determines the memory type used to access the PD Table.
    pwt: bool = false,
    /// Page-level cache disable.
    /// Indirectly determines the memory type used to access the PD Table.
    pcd: bool = false,
    /// Accessed.
    /// Indicates wheter this entry has been used for translation.
    accessed: bool = false,
    /// Ignored.
    _ignored1: u1 = 0,
    /// Page Size.
    /// If set to true, the entry maps a 1GiB page.
    /// If set to false, the entry references a PD Table.
    ps: bool,
    /// Ignored
    _ignored2: u3 = 0,
    /// Ignored except for HLAT paging.
    restart: bool = false,
    /// 4KB aligned address of the PD Table.
    phys_pdt: u52,

    /// Get a new PDPT entry with the present bit set to false.
    pub fn new_nopresent() PdptEntry {
        return PdptEntry{
            .present = false,
            .rw = false,
            .us = false,
            .ps = false,
            .phys_pdt = 0,
        };
    }

    /// Get a new PDPT entry.
    pub fn new(phys_pdt: u64) PdptEntry {
        return PdptEntry{
            .present = true,
            .rw = true,
            .us = false,
            .ps = false,
            .phys_pdt = @truncate(phys_pdt >> page_shift),
        };
    }
};

/// PDT Entry
const PdtEntry = packed struct(u64) {
    /// Present.
    present: bool = true,
    /// Read/Write.
    /// If set to false, wirte access is not allowed to the 2MiB region.
    rw: bool,
    /// User/Supervisor.
    /// If set to false, user-mode access is not allowed to the 2Mib region.
    us: bool,
    /// Page-level writh-through.
    /// Indirectly determines the memory type used to access the 2MiB page or Page Table.
    pwt: bool = false,
    /// Page-level cache disable.
    /// Indirectly determines the memory type used to access the 2MiB page or Page Table.
    pcd: bool = false,
    /// Accessed.
    /// Indicates wheter this entry has been used for translation.
    accessed: bool = false,
    /// Dirty bit.
    /// Indicates wheter software has written to the 2MiB page.
    /// Ignored when this entry references a Page Table.
    dirty: bool = false,
    /// Page Size.
    /// If set to true, the entry maps a 2Mib page.
    /// If set to false, the entry references a Page Table.
    ps: bool,
    /// Ignored when CR4.PGE != 1.
    /// Ignored when this entry references a 2MiB page.
    global: bool = false,
    /// Ignored
    _ignored2: u2 = 0,
    /// Ignored except for HLAT paging.
    restart: bool = false,
    /// When the entry maps a 2MiB page, physical address of the 2MiB page.
    /// When the entry references a Page Table, 4KB aligned address of the Page Table.
    phys_pt: u52,

    /// Get a new PDT entry with the present bit set to false.
    pub fn new_nopresent() PdtEntry {
        return PdtEntry{
            .present = false,
            .rw = false,
            .us = false,
            .ps = false,
            .phys_pt = 0,
        };
    }

    /// Get a new PDT entry that maps a 2MiB page.
    pub fn new_4mb(phys: u64) PdtEntry {
        return PdtEntry{
            .present = true,
            .rw = true,
            .us = false,
            .ps = true,
            .phys_pt = @truncate(phys >> 12),
        };
    }
};
