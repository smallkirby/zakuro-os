//! Page allocator that manages physical pages using a simple bitmap.

const std = @import("std");
const log = std.log.scoped(.bpa);

const zakuro = @import("zakuro");
const arch = zakuro.arch;
const page = @import("page.zig");
const MemoryMap = @import("uefi.zig").MemoryMap;

const Self = @This();
const BitmapPageAllocator = @This();

const page_size = arch.page_size;
const Pfn = page.Pfn;

/// The maximum bytes of memory that can be managed by this allocator.
const max_mem_size: usize = 128 * 1024 * 1024 * 1024; // 128 GiB
/// The number of page frames that can be managed by this allocator.
const max_frames: usize = max_mem_size / page_size;
/// The number of bytes required to store the state of each page frame.
const num_ents_bitmap: usize = max_frames / 8;
/// The number of frames that can be managed by each byte of the bitmap.
const frames_per_byte: usize = 8;

/// A bitmap mapping the state of physical pages.
bitmap: [num_ents_bitmap]u8 = [_]u8{0} ** num_ents_bitmap,
/// Start of the physical address range managed by this allocator.
start_pfn: usize = 0,
/// End of the physical address range managed by this allocator.
end_pfn: usize = 0,

/// Get a instance of the page allocator.
/// Once this function is called, the memory map is no longer usable.
pub fn init(map: *MemoryMap, buffer: []u8) *Self {
    if (buffer.len < @sizeOf(Self)) {
        @panic("BitmapPageAllocator: buffer is too small");
    }
    var descriptor = map.next(null);
    var avail_end: usize = 0;
    const self: *Self = @alignCast(@ptrCast(buffer.ptr));
    @memset(&self.bitmap, 0);

    // Iterate over the memory map and record page states.
    while (descriptor != null) : (descriptor = map.next(descriptor)) {
        const desc = descriptor.?;

        log.debug("0x{X:0>16} - 0x{X:0>16} : {s}", .{
            desc.physical_start,
            desc.physical_start + desc.num_pages * page_size,
            @tagName(desc.typ),
        });

        if (desc.physical_start >= max_mem_size) continue;

        if (avail_end < desc.physical_start) {
            // There is a gap before the region described by the descriptor.
            self.mark(
                page.phys2pfn(avail_end),
                (desc.physical_start - avail_end) / page_size,
                .Unusable,
            );
        }

        const phys_end = desc.physical_start + desc.num_pages * page_size;
        if (desc.typ.isAvailable()) {
            self.mark(
                page.phys2pfn(desc.physical_start),
                desc.num_pages,
                .Usable,
            );
            avail_end = phys_end;
        } else {
            self.mark(
                page.phys2pfn(desc.physical_start),
                desc.num_pages,
                .Unusable,
            );
        }
    }

    self.start_pfn = 1;
    self.end_pfn = page.phys2pfn(avail_end);

    var count_pages: usize = 0;
    for (0..max_frames) |i| {
        if (self.get(i) == .Usable) {
            count_pages += 1;
        }
    }
    log.info("Available memory size: {d} MiB", .{count_pages * page_size / 1024 / 1024});

    return self;
}

/// Mark the given range of physical pages as usable or unusable.
fn mark(self: *Self, start: Pfn, size: usize, state: PageState) void {
    for (0..size) |i| {
        self.set(start + i, state);
    }
}

inline fn get(self: *Self, pfn: Pfn) PageState {
    return if ((self.bitmap[pfn / frames_per_byte] >> @as(u3, @truncate(pfn % frames_per_byte))) & 1 != 0)
        .Usable
    else
        .Unusable;
}

inline fn set(self: *Self, pfn: Pfn, state: PageState) void {
    if (state == .Unusable) {
        self.bitmap[pfn / frames_per_byte] &= ~(@as(u8, 1) << @as(u3, @truncate(pfn % frames_per_byte)));
    } else {
        self.bitmap[pfn / frames_per_byte] |= @as(u8, 1) << @as(u3, @truncate(pfn % frames_per_byte));
    }
}

const PageState = enum(u1) {
    /// Page is already allocated or unusable.
    Unusable = 0,
    /// Page can be used.
    Usable = 1,
};

const testing = std.testing;

test "bitmap size" {
    const bpa = BitmapPageAllocator{};
    try testing.expectEqual(num_ents_bitmap, @sizeOf(@TypeOf(bpa.bitmap)));
}

test "bitmap operation" {
    var bpa = BitmapPageAllocator{};
    try testing.expectEqual(0b0000_0000, bpa.bitmap[0]);

    bpa.set(0, .Usable);
    bpa.set(3, .Usable);
    bpa.set(6, .Usable);
    try testing.expectEqual(0b0100_1001, bpa.bitmap[0]);
    bpa.set(3, .Unusable);
    try testing.expectEqual(0b0100_0001, bpa.bitmap[0]);
    bpa.set(3, .Unusable);
    try testing.expectEqual(0b0100_0001, bpa.bitmap[0]);
    bpa.set(10, .Usable);
    try testing.expectEqual(0b0000_0100, bpa.bitmap[1]);

    try testing.expectEqual(.Usable, bpa.get(0));
    try testing.expectEqual(.Unusable, bpa.get(1));
    try testing.expectEqual(.Unusable, bpa.get(3));
    try testing.expectEqual(.Usable, bpa.get(6));
    try testing.expectEqual(.Unusable, bpa.get(9));
    try testing.expectEqual(.Usable, bpa.get(10));
}
