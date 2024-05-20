//! This file defines DWARF DIE (Debugging Information Entry) and related structures.
//! DIEs are stored in .debug_info section of ELF files.
//!
//! One DIE tree consists of a compilation unit header,
//! followed by a single DW_TAG_compile_unit or DW_TAG_pratial_unit DIE and its children.
//!
//! Each DIE refers to an abbreviation declaration in .debug_abbrev section.
//! The decl contains the abbribute name and format,
//! and the DIE contains the actual attribute values.
//!
//! For the format and data representation of DIE,
//! refer to Chapter 7.5 (Page.198) of DWARF 5 standard.
//!
//! Note that this impl currently supports only DWARF v4 32-bit format.

const std = @import("std");
const leb = std.leb;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Elf = @import("elf.zig").Elf;
const encoding = @import("encoding.zig");
const AttributeName = encoding.AttributeName;
const AttributeForm = encoding.AttributeForm;
const AbbrevTable = @import("AbbreviationTable.zig");
const Attribute = AbbrevTable.Attribute;

const Self = @This();
const CompilationUnit = Self;

/// Parse ELF's .debug_info section and constructs DIE trees.
pub fn parse(elf: Elf, abbr_tables: []AbbrevTable, allocator: Allocator) !void {
    _ = allocator;

    const info = elf.debug_info;
    var stream = std.io.fixedBufferStream(info);
    var crdr = std.io.countingReader(stream.reader());
    const rdr = crdr.reader();

    while (crdr.bytes_read != info.len) {
        const length_short = try rdr.readInt(u32, .little);
        const version = try rdr.readInt(u16, .little);
        const abbrev_offset = try rdr.readInt(u32, .little);
        const addr_size = try rdr.readInt(u8, .little);
        const unit = CompilationUnitHeader{
            .unit_length_short = length_short,
            .version = version,
            .abbrev_offset = abbrev_offset,
            .address_size = addr_size,
        };

        if (length_short == 0xFFFF_FFFF) {
            @panic("64-bit DWARF format is not supported.");
        }
        if (version != 4) {
            @panic("Unsupported DWARF version.");
        }
        if (addr_size != 8) {
            @panic("Unsupported address size.");
        }

        // Parse all compilation units.
        const tbl = AbbrevTable.findTbl(abbr_tables, abbrev_offset) orelse @panic("Abbrev table not found.");
        const len = length_short + @sizeOf(@TypeOf(length_short)); // NOTE: DWARF bit specific
        try parseDie(
            false,
            unit,
            elf,
            (crdr.bytes_read - 11) + len,
            tbl,
            crdr,
            rdr,
        );
    }
}

/// Parse a DIE and all its children recursively for the current compilation unit.
fn parseDie(
    /// Whether this DIE has a parent DIE.
    parent: bool,
    /// Root compilation unit header.
    unit: CompilationUnitHeader,
    /// ELF binary
    elf: Elf,
    /// The offset of the end of this compilation unit starting from the start of .debug_info.
    until: usize,
    /// Abbreviation tables parsed from .debug_abbrev
    tbl: AbbrevTable,
    /// Counting reader
    crdr: anytype,
    /// Reader
    rdr: anytype,
) !void {
    while (crdr.bytes_read != until) {
        const abbrev_code = try leb.readULEB128(u64, rdr);
        if (abbrev_code == 0) {
            // If this DIE is a children, go back to the parent layer.
            // If this DIE does not have a parent, continue parsing siblings.
            if (parent) return else continue;
        }
        const decl = tbl.findDecl(abbrev_code) orelse @panic("Abbr decl not found.");

        // Parse all attributes in this DIE.
        for (decl.attributes) |attr| {
            try readAttribute(unit, attr, rdr, elf);
        }

        std.debug.print("=====================================\n", .{});
        if (decl.has_children == .HasChildren) {
            try parseDie(
                true,
                unit,
                elf,
                until,
                tbl,
                crdr,
                rdr,
            );
        }
    }
}

/// Read a single attribute data and advance the reader.
fn readAttribute(
    unit: CompilationUnitHeader,
    /// Abbreviation declaration.
    attr: Attribute,
    /// Reader
    rdr: anytype,
    /// ELF binary
    elf: Elf,
) !void {
    _ = unit;

    switch (attr.form) {
        .Addr => {
            const addr = try rdr.readInt(u64, .little);
            std.debug.print("\taddr: {X}\n", .{addr});
        },
        .Strp => {
            const offset = try rdr.readInt(u32, .little); // NOTE: DWARF bit specific
            const str = elf.debugStr(offset).?;
            std.debug.print("\tstrp: {s} (offset=0x{X})\n", .{ str, offset });
        },
        .Data1 => {
            const data = try rdr.readInt(u8, .little);
            std.debug.print("\tdata2: 0x{X}\n", .{data});
        },
        .Data2 => {
            const data = try rdr.readInt(u16, .little);
            std.debug.print("\tdata2: 0x{X}\n", .{data});
        },
        .Data4 => {
            const data = try rdr.readInt(u32, .little);
            std.debug.print("\tdata2: 0x{X}\n", .{data});
        },
        .Data8 => {
            const data = try rdr.readInt(u64, .little);
            std.debug.print("\tdata2: 0x{X}\n", .{data});
        },
        .SData => {
            const data = try leb.readILEB128(i64, rdr);
            std.debug.print("\tudata: {X}\n", .{data});
        },
        .UData => {
            const data = try leb.readULEB128(u64, rdr);
            std.debug.print("\tidata: {X}\n", .{data});
        },
        .SecOffset => {
            _ = try rdr.readInt(u32, .little); // NOTE: DWARF bit specific
        },
        .FlagPresent => {},
        .Flag => {
            const data = try rdr.readByte() != 0;
            std.debug.print("\tpresent: {}\n", .{data});
        },
        .Ref1 => {
            const offset = try rdr.readInt(u8, .little);
            std.debug.print("\toffset: {X}\n", .{offset});
        },
        .Ref2 => {
            const offset = try rdr.readInt(u16, .little);
            std.debug.print("\toffset: {X}\n", .{offset});
        },
        .Ref4 => {
            const offset = try rdr.readInt(u32, .little);
            std.debug.print("\toffset: {X}\n", .{offset});
        },
        .Ref8 => {
            const offset = try rdr.readInt(u64, .little);
            std.debug.print("\toffset: {X}\n", .{offset});
        },
        .Exprloc => {
            const length = try leb.readULEB128(u64, rdr);
            try rdr.skipBytes(length, .{});
            std.debug.print("\tlength: {X}\n", .{length});
        },
        .Block1 => {
            const length = try rdr.readInt(u8, .little);
            try rdr.skipBytes(length, .{});
            std.debug.print("\tlength: {X}\n", .{length});
        },
        .Block2 => {
            const length = try rdr.readInt(u16, .little);
            try rdr.skipBytes(length, .{});
            std.debug.print("\tlength: {X}\n", .{length});
        },
        .Block4 => {
            const length = try rdr.readInt(u32, .little);
            try rdr.skipBytes(length, .{});
            std.debug.print("\tlength: {X}\n", .{length});
        },
        .Block => {
            const length = try leb.readULEB128(u64, rdr);
            try rdr.skipBytes(length, .{});
            std.debug.print("\tlength: {X}\n", .{length});
        },
        .String,
        .RefAddr,
        .RefUData,
        .Indirect,
        .RefSig8,
        => @panic("Unimplemented type of DIE attribute format"),
        .Reserved => @panic("The DIE's attribute has RESERVED type format."),
    }
}

/// Unit header for DWARF v4 32-bit format.
const CompilationUnitHeader = packed struct {
    /// In the 64-bit DWARF format, this must be 0xFFFF_FFFF.
    unit_length_short: u32,

    // In DWARF 64-bit format, 64bit length is inserted here. //

    /// DWARF version.
    version: u16,

    // In DWARF v5, unit_type is inserted here. //

    /// Associates the compilation unit with a particular set of DIE abbreviations.
    /// Note: The order of this field and address_size is swapped in DWARF v5.
    abbrev_offset: u32,
    /// Size in bytes of an address on the target arch.
    address_size: u8,
};

const testing = std.testing;

test "Parse compilation units and its DIE children" {
    const bin align(0x100) = @embedFile("dwarf-elf").*;
    const allocator = std.heap.page_allocator;
    const elf = try Elf.new(&bin, allocator);
    const abbr_tbls = try AbbrevTable.parse(elf, allocator);

    try parse(elf, abbr_tbls, allocator);
}
