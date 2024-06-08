//! This provides a minimal ELF parser for the purpose of reading sections
//! that are needed for DWARF debugging information.

const std = @import("std");

pub const ElfError = error{
    /// Invalid ELF header
    InvalidHeader,
    /// Some section is not found
    SectionNotFound,
};

/// ELF file format
pub const Elf = struct {
    /// debug_info section
    debug_info: []const u8,
    /// debug_loc section
    debug_loc: []const u8,
    /// debug_abbrev section
    debug_abbrev: []const u8,
    /// debug_aranges section
    debug_ranges: []const u8,
    /// debug_str section
    debug_str: []const u8,
    /// debug_line section
    debug_line: []const u8,
    // ELF header
    header: ElfHeader,

    /// ELF binary
    bin: [*]const u8,

    const Self = @This();

    pub fn new(bin: [*]const u8) ElfError!Self {
        const header = try ElfHeader.new(bin);
        var self = Self{
            .debug_info = undefined,
            .debug_loc = undefined,
            .debug_abbrev = undefined,
            .debug_ranges = undefined,
            .debug_str = undefined,
            .debug_line = undefined,
            .header = header,
            .bin = bin,
        };

        const err = ElfError.SectionNotFound;
        const debug_info = self.sectionHeader(".debug_info") orelse return err;
        const debug_loc = self.sectionHeader(".debug_loc") orelse return err;
        const debug_abbrev = self.sectionHeader(".debug_abbrev") orelse return err;
        const debug_ranges = self.sectionHeader(".debug_ranges") orelse return err;
        const debug_str = self.sectionHeader(".debug_str") orelse return err;
        const debug_line = self.sectionHeader(".debug_line") orelse return err;

        self.debug_info = (bin + debug_info.offset)[0..debug_info.size];
        self.debug_loc = (bin + debug_loc.offset)[0..debug_loc.size];
        self.debug_abbrev = (bin + debug_abbrev.offset)[0..debug_abbrev.size];
        self.debug_ranges = (bin + debug_ranges.offset)[0..debug_ranges.size];
        self.debug_str = (bin + debug_str.offset)[0..debug_str.size];
        self.debug_line = (bin + debug_line.offset)[0..debug_line.size];

        return self;
    }

    /// Get the section header of the given name.
    fn sectionHeader(self: *const Self, name: []const u8) ?SectionHeader {
        const header = self.header;
        const shstrtab = header.shstrtab;

        for (0..header.fheader.shnum) |i| {
            const sh: *const SectionHeader = @alignCast(@ptrCast(self.bin + header.fheader.shoff + i * header.fheader.shentsize));
            const sh_name = shstrtab.strtabAt(sh.name) orelse continue;
            if (std.mem.eql(u8, sh_name, name)) {
                return sh.*;
            }
        }

        return null;
    }

    /// Get the debug string from .debug_str section.
    pub fn debugStr(self: Self, offset: u64) ?[]const u8 {
        for (self.debug_str[offset..], 0..) |c, i| {
            if (c == 0) {
                return self.debug_str[offset .. offset + i];
            }
        }

        return null;
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
        for (self.table[offset..], 0..) |c, i| {
            if (c == 0) {
                return self.table[offset .. offset + i];
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
    const bin align(0x100) = @embedFile("dwarf-elf").*;

    try testing.expectEqual(@offsetOf(ElfHeader.FixedHeader, "shoff"), 0x28);
    try testing.expectEqual(@offsetOf(ElfHeader.FixedHeader, "flags"), 0x30);
    try testing.expectEqual(@offsetOf(ElfHeader.FixedHeader, "shnum"), 0x3C);

    const header = try ElfHeader.new(&bin);
    try testing.expectEqual(header.fheader.shnum, 22);

    try testing.expect(std.mem.eql(u8, "", header.shstrtab.strtabAt(0).?));
    try testing.expect(std.mem.eql(u8, ".rodata", header.shstrtab.strtabAt(1).?));
}

test "Can parse necessary sections and init ERF struct" {
    const bin align(0x100) = @embedFile("dwarf-elf").*;
    _ = try Elf.new(&bin);
}
