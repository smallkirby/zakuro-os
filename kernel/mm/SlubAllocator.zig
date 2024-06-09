//! Simple general use allocator that mimics slub system.
//! This allocator can handle up to 4 KiB of objects,
//! and delegates to a page allocator for larger objects.

const std = @import("std");
const log = std.log.scoped(.kalloc);
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const zakuro = @import("zakuro");
const arch = zakuro.arch;
const page_size = arch.page_size;
const page = @import("page.zig");
const BitmapPageAllocator = @import("BitmapPageAllocator.zig");

pub const KAllocator = @This();
const Self = KAllocator;

pub const SlubAllocatorError = Error;
const Error = error{
    /// The requested size is zero.
    ZeroSize,
    /// The fixed sized buffer for the allocator is full.
    MetadataNoMemory,
    /// Out of memory.
    NoMemory,
};

arena: Arena,
bpa: *BitmapPageAllocator,

/// Instantiate the slub allocator.
pub fn init(bpa: *BitmapPageAllocator) Error!Self {
    return Self{
        .arena = try Arena.init(bpa),
        .bpa = bpa,
    };
}

/// Get the allocator.
pub fn allocator(self: *Self) Allocator {
    return Allocator{
        .ptr = self,
        .vtable = &.{
            .alloc = alloc,
            .resize = resize,
            .free = free,
        },
    };
}

fn alloc(_: *anyopaque, _: usize, _: u8, _: usize) ?[*]u8 {
    @panic("Not implemented");
}

/// Not implemented.
fn resize(
    _: *anyopaque,
    _: []u8,
    _: u8,
    _: usize,
    _: usize,
) bool {
    @setCold(true);
    @panic("SlubAllocator: resize is not supported");
}

fn free(
    _: *anyopaque,
    _: []u8,
    _: u8,
    _: usize,
) void {
    @panic("Not implemented");
}

/// Virtual address.
const va = u64;

/// Sizes of the slubs.
const slub_sizes = [_]usize{ 8, 16, 32, 64, 96, 128, 192, 256, 512, 1024, 2048, 4096 };
/// Converts the size to the index of the slub.
fn slubsize2index(size: usize) usize {
    return switch (size) {
        8 => 0,
        16 => 1,
        32 => 2,
        64 => 3,
        96 => 4,
        128 => 5,
        192 => 6,
        256 => 7,
        512 => 8,
        1024 => 9,
        2048 => 10,
        4096 => 11,
        else => unreachable,
    };
}

/// Internal state of the slub allocator.
const Arena = struct {
    /// Slubs of each size.
    slubs: [slub_sizes.len]Slub,

    pub fn init(bpa: *BitmapPageAllocator) Error!Arena {
        var slubs: [slub_sizes.len]Slub = undefined;
        for (slub_sizes) |size| {
            const index = slubsize2index(size);
            slubs[index] = try Slub.init(size, bpa);
        }
        return Arena{
            .slubs = slubs,
        };
    }
};

/// List entry of pages.
const PageList = std.DoublyLinkedList(PageData);
/// Page data.
const PageData = packed struct {
    /// The start address of the page.
    addr: va,
};

/// Single slub of the size.
const Slub = struct {
    /// The size of objects this slub can hold.
    size: usize,
    /// Active page that can allocate at least one object.
    active_page: va,
    /// List of pages that are full.
    freelist: PageList,
    /// List of pages that are not full.
    pagelist: PageList,

    /// Instantiate
    pub fn init(size: usize, bpa: *BitmapPageAllocator) Error!Slub {
        const first_page = bpa.getAdjacentPages(1) orelse {
            return Error.NoMemory;
        };
        return Slub{
            .size = size,
            .active_page = page.pfn2phys(first_page),
            .freelist = .{},
            .pagelist = .{},
        };
    }
};

/// Converts the size to the size of the first slub that can hold it.
/// If the size exceeds the maximum slub size, returns null.
fn wrapsMemorySize(size: usize) Error!?usize {
    if (size == 0) {
        return Error.ZeroSize;
    }
    if (size > slub_sizes[slub_sizes.len - 1]) {
        return null;
    }

    for (slub_sizes) |slub_size| {
        if (size <= slub_size) {
            return slub_size;
        }
    }

    unreachable;
}

const testing = std.testing;

test "wrapsMemorySize" {
    const get = wrapsMemorySize;
    try testing.expectEqual(8, get(1));
    try testing.expectEqual(8, get(8));
    try testing.expectEqual(16, get(9));
    try testing.expectEqual(16, get(16));
    try testing.expectEqual(32, get(17));
    try testing.expectEqual(32, get(32));
    try testing.expectEqual(64, get(33));
    try testing.expectEqual(64, get(64));
    try testing.expectEqual(96, get(65));
    try testing.expectEqual(96, get(96));
    try testing.expectEqual(128, get(97));
    try testing.expectEqual(128, get(128));
    try testing.expectEqual(192, get(129));
    try testing.expectEqual(192, get(192));
    try testing.expectEqual(256, get(193));
    try testing.expectEqual(256, get(256));
    try testing.expectEqual(512, get(257));
    try testing.expectEqual(512, get(512));
    try testing.expectEqual(1024, get(513));
    try testing.expectEqual(1024, get(1024));
    try testing.expectEqual(2048, get(1025));
    try testing.expectEqual(2048, get(2048));
    try testing.expectEqual(4096, get(2049));
    try testing.expectEqual(4096, get(4096));

    try testing.expectError(Error.ZeroSize, get(0));
    try testing.expectEqual(null, get(4097));
}

test {
    testing.refAllDecls(@This());
}
