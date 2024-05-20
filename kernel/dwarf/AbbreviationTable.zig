//! This file defines DWARF Abberviations Table.
//! The abbreviations table for a compilation unit consists of a set of abbreviation declarations.
//! These declarations are used to decode the abbreviation codes in the abbreviation section of the .debug_info section.
//! The table is parsed from the .debug_abbrev section of an ELF file.

const std = @import("std");
const leb = std.leb;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Elf = @import("elf.zig").Elf;
const encoding = @import("encoding.zig");
const TagEncoding = encoding.TagEncoding;
const ChildDetermination = encoding.ChildDetermination;
const AttributeName = encoding.AttributeName;
const AttributeForm = encoding.AttributeForm;

const Self = @This();
const AbbreviationTable = Self;

/// List of abbreviation declaration in this table.
/// Be aware that the code can differ from the index inside this slice.
decls: []Declaration,
/// Offset from the start of .debug_abbrev secion.
offset: usize,

/// Parse ELF's .debug_abbrev section and constructs Abbreviation Tables.
pub fn parse(elf: Elf, allocator: Allocator) ![]Self {
    const abbrev = elf.debug_abbrev;
    var stream = std.io.fixedBufferStream(abbrev);
    var crdr = std.io.countingReader(stream.reader());
    const rdr = crdr.reader();

    var tables = ArrayList(Self).init(allocator);
    errdefer tables.deinit();

    // Parse all tables.
    while (crdr.bytes_read != abbrev.len) {
        const tbl_offset = crdr.bytes_read;

        var decls = ArrayList(Declaration).init(allocator);
        errdefer decls.deinit();

        // Parse all declarations in this table.
        while (true) {
            const code = try leb.readULEB128(u64, rdr);
            if (code == 0) break;
            const tag = try leb.readULEB128(u64, rdr);
            const has_children = try rdr.readByte();
            var attributes = ArrayList(Attribute).init(allocator);
            errdefer attributes.deinit();

            var decl = Declaration{
                .code = code,
                .tag = @enumFromInt(tag),
                .has_children = @enumFromInt(has_children),
                .attributes = undefined,
            };

            // Parse all attributes in this decl.
            while (true) {
                const name = try leb.readULEB128(u64, rdr);
                const form = try leb.readULEB128(u64, rdr);
                if (name == 0 and form == 0) break;

                try attributes.append(.{
                    .name = AttributeName.from(name),
                    .form = @enumFromInt(form),
                });
            }

            decl.attributes = try attributes.toOwnedSlice();
            try decls.append(decl);
        }

        try tables.append(.{
            .decls = try decls.toOwnedSlice(),
            .offset = tbl_offset,
        });
    }

    return tables.toOwnedSlice();
}

/// Find an abbreviation decl specified by the code.
pub fn findDecl(self: *const Self, code: u64) ?Declaration {
    for (self.decls) |decl| {
        if (decl.code == code) return decl;
    }

    return null;
}

/// Find an abbreviation table specified by the offset.
pub fn findTbl(tbls: []Self, offset: usize) ?Self {
    for (tbls) |tbl| {
        if (tbl.offset == offset) return tbl;
    }

    return null;
}

/// Single declaration in an abbreviation table.
const Declaration = struct {
    /// Code of this decl.
    code: u64,
    /// Tag encoding.
    tag: TagEncoding,
    /// Whether this decl has children.
    has_children: ChildDetermination,
    /// Attributes, excluding terminal NULL attribute.
    attributes: []Attribute,
};

pub const Attribute = struct {
    name: AttributeName,
    form: AttributeForm,
};

const testing = std.testing;

test "Parse abbreviation table" {
    const bin align(0x100) = @embedFile("dwarf-elf").*;
    const elf = try Elf.new(&bin, std.heap.page_allocator);

    const tables = try parse(elf, std.heap.page_allocator);
    for (tables) |tbl| {
        try testing.expect(tbl.decls.len >= 10);
    }

    const inlined_sub = tables[0].decls[32];
    try testing.expectEqual(inlined_sub.code, 33);
    try testing.expectEqual(inlined_sub.has_children, .NoChildren);
    try testing.expectEqual(inlined_sub.tag, .InlinedSubroutine);
    try testing.expectEqual(inlined_sub.attributes.len, 6);
}
