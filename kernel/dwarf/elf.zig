//! This provides a minimal ELF parser for the purpose of reading sections
//! that are needed for DWARF debugging information.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const ElfError = error{
    /// Invalid ELF header
    InvalidHeader,
};

/// ELF file format
pub const Elf = struct {
    /// debug_info section
    debug_info: []u8,
    /// debug_loc section
    debug_loc: []u8,
    /// debug_abbrev section
    debug_abbrev: []u8,
    /// debug_aranges section
    debug_ranges: []u8,
    /// debug_str section
    debug_str: []u8,
    /// debug_line section
    debug_line: []u8,
    // ELF header
    header: ElfHeader,

    /// Memory allocator used internally
    allocator: Allocator,

    const Self = @This();

    pub fn new(bin: [*]const u8, allocator: Allocator) Self {
        _ = bin; // autofix

        return Self{
            .debug_info = undefined,
            .debug_loc = undefined,
            .debug_abbrev = undefined,
            .debug_ranges = undefined,
            .debug_str = undefined,
            .debug_line = undefined,
            .header = undefined,
            .allocator = allocator,
        };
    }
};

/// ELF header.
const ElfHeader = struct {
    const Self = @This();

    /// ELF binary
    bin: [*]const u8,
    /// First part of the ELF header that has fixed size.
    fheader: FixedHeader,
    /// Section header string table.
    shstrtab: Shstrtab,

    /// The parsed ELF header that has fixed size.
    const FixedHeader = extern struct {
        /// Magic
        ident: [4]u8,
        /// ELF class (bits)
        class: enum(u8) {
            ELF32 = 1,
            ELF64 = 2,
        },
        /// Endianness
        data: enum(u8) {
            Little = 1,
            Big = 2,
        },
        /// ELF version (set to 1)
        version: enum(u8) {
            Current = 1,
        },
        /// OS ABI
        osabi: u8,
        abiversion: u8,
        pad: [7]u8,
        /// Object file type
        etype: enum(u16) {
            Executable = 2,
        },
        machine: u16,
        eversion: u32,
        /// Pointer to the entry point
        entry: u64,
        /// Offset to the program header table
        phoff: u64,
        /// Offset to the section header table
        shoff: u64,
        flags: u32,
        /// ELF header size
        ehsize: u16,
        phentsize: u16,
        phnum: u16,
        shentsize: u16,
        shnum: u16,
        shstrndx: u16,
    };

    /// Check the validity of the ELF header and return it.
    /// Caller MUST not preserve the memory of the ELF header.
    pub fn new(bin: [*]const u8) ElfError!Self {
        const header: *const FixedHeader = @alignCast(@ptrCast(bin));

        if (!std.mem.eql(u8, header.ident[0..4], "\x7FELF")) {
            return ElfError.InvalidHeader;
        }
        if (header.class != .ELF64) {
            return ElfError.InvalidHeader;
        }
        if (header.data != .Little) {
            return ElfError.InvalidHeader;
        }
        if (header.version != .Current) {
            return ElfError.InvalidHeader;
        }
        if (header.etype != .Executable) {
            return ElfError.InvalidHeader;
        }
        if (header.eversion != 1) {
            return ElfError.InvalidHeader;
        }

        const header_shstrtab: *const SectionHeader = @alignCast(@ptrCast(bin + header.shoff + header.shstrndx * header.shentsize));
        const shstrtab_bin: [*]const u8 = @ptrCast(bin + header_shstrtab.offset);
        const shstrtab = Shstrtab{
            .table = shstrtab_bin[0..header_shstrtab.size],
        };

        return Self{
            .bin = bin,
            .fheader = header.*,
            .shstrtab = shstrtab,
        };
    }
};

const SectionHeader = extern struct {
    /// Offset to a string in the .shstrtab section.
    name: u32,
    /// Type of the header.
    shtype: SectionType,
    flags: u64,
    addr: u64,
    /// Offset to the section in the file.
    offset: u64,
    /// Size in bytes of the section.
    size: u64,
    link: u32,
    info: u32,
    addralign: u64,
    /// Size of each entry in the section.
    entsize: u64,
};

const Shstrtab = struct {
    /// Slice of the .shstrtab section.
    table: []const u8,

    const Self = @This();

    /// Get a string at the given offset.
    pub fn strtabAt(self: *const Self, offset: u64) ?[]const u8 {
        var ent_start: ?usize = if (offset == 0) 0 else null;
        var cur: u64 = 0;

        for (self.table, 0..) |c, i| {
            if (c == 0) {
                if (ent_start) |start| {
                    return self.table[start..i];
                }

                cur += 1;
                if (cur == offset) {
                    ent_start = i + 1;
                }
            }
        }

        return null;
    }
};

const SectionType = enum(u32) {
    Null = 0,
    ProgBits = 1,
    SymTab = 2,
    StrTab = 3,
    Rela = 4,
    Hash = 5,
    Dynamic = 6,
    Note = 7,
    NoBits = 8,
    Rel = 9,
    ShLib = 10,
    DynSym = 11,
    InitArray = 14,
    FiniArray = 15,
    PreInitArray = 16,
    Group = 17,
    SymTabShIndex = 18,
    Num = 19,
    LoOS = 0x60000000,
};

test {
    std.testing.refAllDecls(@This());
}

const testing = std.testing;

test "Can parse ELF header and shstrtab" {
    const bin align(64) = @embedFile("dwarf-elf").*;

    try testing.expectEqual(@offsetOf(ElfHeader.FixedHeader, "shoff"), 0x28);
    try testing.expectEqual(@offsetOf(ElfHeader.FixedHeader, "flags"), 0x30);
    try testing.expectEqual(@offsetOf(ElfHeader.FixedHeader, "shnum"), 0x3C);

    const header = try ElfHeader.new(&bin);
    try testing.expectEqual(header.fheader.shnum, 21);

    try testing.expect(std.mem.eql(u8, "", header.shstrtab.strtabAt(0).?));
    try testing.expect(std.mem.eql(u8, ".rodata", header.shstrtab.strtabAt(1).?));
    try testing.expect(std.mem.eql(u8, ".text", header.shstrtab.strtabAt(4).?));
    try testing.expect(std.mem.eql(u8, ".debug_info", header.shstrtab.strtabAt(11).?));
    try testing.expect(std.mem.eql(u8, ".strtab", header.shstrtab.strtabAt(20).?));
}
