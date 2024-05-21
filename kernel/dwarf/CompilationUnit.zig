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
//!
//! ==============================================================================
//!
//! LICENCE NOTICE
//!
//! The implementation is heavily inspired by https://github.com/kubkon/zig-dwarfdump .
//! Original LICENCE follows:
//!
//! MIT License
//!
//! Copyright (c) 2022 Jakub Konka
//!
//! Permission is hereby granted, free of charge, to any person obtaining a copy
//! of this software and associated documentation files (the "Software"), to deal
//! in the Software without restriction, including without limitation the rights
//! to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//! copies of the Software, and to permit persons to whom the Software is
//! furnished to do so, subject to the following conditions:
//!
//! The above copyright notice and this permission notice shall be included in all
//! copies or substantial portions of the Software.
//!
//! THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//! IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//! FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//! AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//! LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//! OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//! SOFTWARE.
//!

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

/// Header of this compilation unit
header: CompilationUnitHeader,
/// All DIEs this compilation unit contains.
/// The tree relationship is determined by `children` field.
dies: ArrayList(Die),
/// Children DIE.
/// The entries are index of DIEs(`dies`).
children: ArrayList(DieIndex),
/// Abbreviation Table this compilation unit uses.
tbl: AbbrevTable,
/// Memory allocator.
allocator: Allocator,

/// Parse ELF's .debug_info section and constructs DIE trees.
pub fn parse(elf: Elf, abbr_tables: []AbbrevTable, allocator: Allocator) ![]Self {
    var cus = ArrayList(Self).init(allocator);
    errdefer cus.deinit();

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

        const tbl = AbbrevTable.findTbl(abbr_tables, abbrev_offset) orelse @panic("Abbrev table not found.");
        var cu = Self{
            .header = unit,
            .dies = ArrayList(Die).init(allocator),
            .children = ArrayList(DieIndex).init(allocator),
            .tbl = tbl,
            .allocator = allocator,
        };

        // Parse all compilation units.
        const len = length_short + @sizeOf(@TypeOf(length_short)); // NOTE: DWARF bit specific
        try cu.parseDie(
            null,
            elf,
            (crdr.bytes_read - 11) + len,
            crdr,
            rdr,
        );

        try cus.append(cu);
    }

    return cus.toOwnedSlice();
}

/// Parse a DIE and all its children recursively for the current compilation unit.
fn parseDie(
    self: *Self,
    /// Index of the parent DIE in the compilation unit.
    parent: ?DieIndex,
    /// ELF binary
    elf: Elf,
    /// The offset of the end of this compilation unit starting from the start of .debug_info.
    until: usize,
    /// Counting reader
    crdr: anytype,
    /// Reader
    rdr: anytype,
) !void {
    const header = self.header;
    const tbl = self.tbl;
    const allocator = self.allocator;

    while (crdr.bytes_read != until) {
        const ix = self.dies.items.len;
        const abbrev_code = try leb.readULEB128(u64, rdr);
        if (abbrev_code == 0) {
            // If this DIE is a children, go back to the parent layer.
            // If this DIE does not have a parent, continue parsing siblings.
            if (parent) |_| return else continue;
        }
        const decl = tbl.findDecl(abbrev_code) orelse @panic("Abbr decl not found.");

        // Parse all attributes in this DIE.
        var attributes = ArrayList([]const u8).init(allocator);
        errdefer attributes.deinit();
        for (decl.attributes) |attr| {
            try attributes.append(try readAttribute(
                header,
                attr,
                rdr,
                elf,
                self.allocator,
            ));
        }

        const die = Die{
            .code = abbrev_code,
            .values = try attributes.toOwnedSlice(),
            .children = ArrayList(DieIndex).init(allocator),
        };
        try self.dies.append(die);

        if (parent) |p| {
            try self.dies.items[p].children.append(ix);
        } else {
            try self.children.append(ix);
        }

        if (decl.has_children == .HasChildren) {
            try self.parseDie(
                ix,
                elf,
                until,
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
    /// Memory allocator
    allocator: Allocator,
) ![]const u8 {
    _ = unit;
    const asBytes = std.mem.asBytes;

    switch (attr.form) {
        .Addr => {
            const addr = try rdr.readInt(u64, .little);
            const p = try allocator.create(u64);
            p.* = addr;
            return asBytes(p);
        },
        .Strp => {
            const offset = try rdr.readInt(u32, .little); // NOTE: DWARF bit specific
            const str = elf.debugStr(offset).?;
            return str;
        },
        .Data1 => return copyBytesForInt(u8, rdr, allocator),
        .Data2 => return copyBytesForInt(u16, rdr, allocator),
        .Data4 => return copyBytesForInt(u32, rdr, allocator),
        .Data8 => return copyBytesForInt(u64, rdr, allocator),
        .SData => return copyBytesForLEB(i64, rdr, allocator),
        .UData => return copyBytesForLEB(u64, rdr, allocator),
        .SecOffset => {
            _ = try rdr.readInt(u32, .little); // NOTE: DWARF bit specific
            return &.{};
        },
        .FlagPresent => return &.{},
        .Flag => {
            const data = try rdr.readByte() != 0;
            return asBytes(&data);
        },
        .Ref1 => return copyBytesForInt(u8, rdr, allocator),
        .Ref2 => return copyBytesForInt(u16, rdr, allocator),
        .Ref4 => return copyBytesForInt(u32, rdr, allocator),
        .Ref8 => return copyBytesForInt(u64, rdr, allocator),
        .Exprloc => {
            const length = try leb.readULEB128(u64, rdr);
            try rdr.skipBytes(length, .{});
            return &.{};
        },
        .Block1 => {
            const length = try rdr.readInt(u8, .little);
            try rdr.skipBytes(length, .{});
            return &.{};
        },
        .Block2 => {
            const length = try rdr.readInt(u16, .little);
            try rdr.skipBytes(length, .{});
            return &.{};
        },
        .Block4 => {
            const length = try rdr.readInt(u32, .little);
            try rdr.skipBytes(length, .{});
            return &.{};
        },
        .Block => {
            const length = try leb.readULEB128(u64, rdr);
            try rdr.skipBytes(length, .{});
            return &.{};
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

pub fn print(self: Self, writer: Writer, allocator: Allocator) !void {
    for (self.dies.items) |*die| {
        try die.print(&self.tbl, writer, allocator);
    }
}

const Code = u64;
const DieIndex = usize;
const Writer = @TypeOf(std.log.debug);

/// Debug Information Entry
const Die = struct {
    /// Code of the abbreviation declaration used by this DIE.
    code: Code,
    /// Raw data of the attributes.
    /// The attribute name and its format can be looked up using the code.
    values: [][]const u8,
    /// Children of this DIE.
    /// This slice contains children DIE's index inside the compilation unit.
    children: ArrayList(DieIndex),

    pub fn print(self: *Die, tbl: *const AbbrevTable, writer: Writer, allocator: Allocator) !void {
        const decl = tbl.findDecl(self.code) orelse return error.DeclNotFound;
        writer("Abbrev Number: {d}", .{self.code}); // TODO
        for (decl.attributes, self.values) |attr, value| {
            writer("\t{s}: {s}", .{ @tagName(attr.name), try printFormat(attr, value, allocator) });
        }
    }

    fn printFormat(attr: Attribute, value: []const u8, allocator: Allocator) ![]const u8 {
        switch (attr.form) {
            .Addr => {
                const v = std.mem.bytesAsValue(u64, value.ptr).*;
                return std.fmt.allocPrint(allocator, "0x{X}", .{v});
            },
            .Strp => return value,
            .Data1,
            .Data2,
            .Data4,
            .Data8,
            .SData,
            .UData,
            => return std.fmt.allocPrint(allocator, "<0x{any}>", .{value}),
            .Ref1 => return std.fmt.allocPrint(allocator, "{d}", .{std.mem.bytesAsValue(u8, value.ptr).*}),
            .Ref2 => return std.fmt.allocPrint(allocator, "{d}", .{std.mem.bytesAsValue(u16, value.ptr).*}),
            .Ref4 => return std.fmt.allocPrint(allocator, "{d}", .{std.mem.bytesAsValue(u32, value.ptr).*}),
            .Ref8 => return std.fmt.allocPrint(allocator, "{d}", .{std.mem.bytesAsValue(u64, value.ptr).*}),
            else => return "???",
        }
    }
};

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

fn copyBytesForInt(T: type, rdr: anytype, allocator: Allocator) ![]const u8 {
    const data = try rdr.readInt(T, .little);
    const p = try allocator.create(T);
    p.* = data;
    return std.mem.asBytes(p);
}

fn copyBytesForLEB(T: type, rdr: anytype, allocator: Allocator) ![]const u8 {
    const data = switch (T) {
        i64 => try leb.readILEB128(T, rdr),
        u64 => try leb.readULEB128(T, rdr),
        else => @panic("Unsupported type for copyByteForLEB()"),
    };
    const p = try allocator.create(T);
    p.* = data;
    return std.mem.asBytes(p);
}

const testing = std.testing;

test "Parse compilation units and its DIE children" {
    const bin align(0x100) = @embedFile("dwarf-elf").*;
    // TODO: use testing allocator
    const allocator = std.heap.page_allocator;
    const elf = try Elf.new(&bin, allocator);
    const abbr_tbls = try AbbrevTable.parse(elf, allocator);

    const cus = try parse(elf, abbr_tbls, allocator);
    try testing.expect(cus.len == 2);
    try testing.expect(cus[0].dies.items.len > 10000);
    try testing.expect(cus[1].dies.items.len > 10000);
}
