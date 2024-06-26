//! Simple general use allocator that mimics slub system.
//! You should use this general-purpose allocator rather than the page allocator
//! unless you are confident that the allocation is large enough.
//! This allocator behaves as same as the page allocator if the requested size is larger than 4 KiB.
//! So it is always reasonable to use this allocator.

const std = @import("std");
const log = std.log.scoped(.slub);
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const zakuro = @import("zakuro");
const arch = zakuro.arch;
const page_size = arch.page_size;
const page = @import("page.zig");
const BitmapPageAllocator = if (!@import("builtin").is_test) @import("BitmapPageAllocator.zig") else MockedPageAllocator;

pub const SlubAllocator = @This();
const Self = SlubAllocator;

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

/// Allocate an memory in the manner of Allocator.
/// Note that the requested `size` is the sum of the size of requested objects.
/// If allocator's alloc(u8, 32) is called, this function's `len` is 32.
/// Note that we align up the size to `log2_align`.
fn alloc(ctx: *anyopaque, len: usize, log2_align: u8, _: usize) ?[*]u8 {
    const self: *Self = @alignCast(@ptrCast(ctx));
    const ptr_align = @as(usize, 1) << @as(Allocator.Log2Align, @intCast(log2_align));
    const aligned_len = if (len % ptr_align == 0) len else len + ptr_align - (len % ptr_align);

    if (wrapsMemorySize(aligned_len) catch unreachable) |slub_size| {
        const slub_index = slubsize2index(slub_size).?;
        const slub = &self.arena.slubs[slub_index];
        return slub.alloc(&self.arena.page_cache, self.bpa) catch null;
    } else {
        const num_page = (aligned_len + page_size - 1) / page_size;
        const pages = self.bpa.getAdjacentPages(num_page) orelse return null;
        return @ptrFromInt(page.pfn2phys(pages));
    }
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
    ctx: *anyopaque,
    buf: []u8,
    log2_align: u8,
    _: usize,
) void {
    const self: *Self = @alignCast(@ptrCast(ctx));
    const len = buf.len;
    const ptr_align = @as(usize, 1) << @as(Allocator.Log2Align, @intCast(log2_align));
    const aligned_len = if (len % ptr_align == 0) len else len + ptr_align - (len % ptr_align);

    if (wrapsMemorySize(aligned_len) catch unreachable) |slub_size| {
        const slub_index = slubsize2index(slub_size).?;
        const slub = &self.arena.slubs[slub_index];
        return slub.free(buf.ptr) catch {};
    } else {
        const num_page = (aligned_len + page_size - 1) / page_size;
        self.bpa.returnAdjacentPages(page.phys2pfn(@intFromPtr(buf.ptr)), num_page);
    }
}

/// Virtual address.
const VA = u64;

/// Sizes of the slubs.
const slub_sizes = [_]usize{ 8, 16, 32, 64, 96, 128, 192, 256, 512, 1024, 2048, 4096 };
/// Converts the size to the index of the slub.
fn slubsize2index(size: usize) ?usize {
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
        else => null,
    };
}

/// Internal state of the slub allocator.
const Arena = struct {
    /// Slubs of each size.
    slubs: [slub_sizes.len]Slub,
    /// Page cache for the slub allocators.
    page_cache: PageStructCache,

    /// Instantiate the arena.
    pub fn init(bpa: *BitmapPageAllocator) Error!Arena {
        var page_cache = try PageStructCache.init(bpa);
        var slubs: [slub_sizes.len]Slub = undefined;
        for (slub_sizes) |size| {
            const index = slubsize2index(size).?;
            slubs[index] = try Slub.init(size, &page_cache, bpa);
        }

        return Arena{
            .slubs = slubs,
            .page_cache = page_cache,
        };
    }
};

/// Linked list of slub pages.
const SlubPageList = std.DoublyLinkedList(SlubPage);
/// Single page used as a slub cache.
const SlubPage = packed struct {
    /// The start address of the page.
    addr: VA,
    /// Pointer to the first element of the free slub object.
    /// If the page is full, this is zero.
    freelist: VA,
};

/// Dedicated allocator for SlubPageList.Node structure under the environment
/// where only page allocator is available.
/// This allocator requests an entire page from the page allocator
/// and uses it to allocate page structures.
/// If the page is full, it requests another page.
/// When the page releases all structures,
/// it returns the page to the page allocator.
/// The allocated page is split into objects.
/// When the object is not used, they contains the pointer to the next object.
const PageStructCache = struct {
    const SlubPageNode = SlubPageList.Node;
    const EmptySlubPageNode = packed struct {
        next: ?*EmptySlubPageNode,
    };

    /// Size of the page struct.
    const node_size: usize = @sizeOf(SlubPageNode);
    /// Number of page struct that can be allocated in a page.
    const node_per_page: usize = page_size / node_size;

    /// Page allocator.
    pa: *BitmapPageAllocator,
    /// Total number of allocated pages.
    num_pages: usize = 0,
    /// Total number of allocated objects.
    num_objects: usize = 0,
    /// Page struct that will be allocated next.
    freelist: ?*EmptySlubPageNode = null,

    /// Instantiate the page cache.
    pub fn init(pa: *BitmapPageAllocator) Error!PageStructCache {
        const cache_pfn = pa.getAdjacentPages(1) orelse return Error.MetadataNoMemory;
        var ret = PageStructCache{
            .pa = pa,
            .freelist = null,
        };

        ret.initPage(page.pfn2phys(cache_pfn));

        return ret;
    }

    /// Allocate a page structure.
    pub fn allocPageStruct(self: *PageStructCache) Error!*SlubPageNode {
        try self.mayAllocNewPage();

        const ret = self.freelist.?;
        self.freelist = ret.next;
        self.num_objects += 1;

        return @alignCast(@ptrCast(ret));
    }

    /// Free a page structure.
    pub fn freePageStruct(self: *PageStructCache, node: *SlubPageNode) Error!void {
        const empty_node: *EmptySlubPageNode = @ptrCast(node);
        empty_node.next = self.freelist orelse @ptrFromInt(0);
        self.freelist = empty_node;
        self.num_objects -= 1;

        // TODO: If the page is empty, return it to the page allocator.
    }

    /// If no more objects can allocate, get a new page.
    /// Otherwise, do nothing.
    fn mayAllocNewPage(self: *PageStructCache) Error!void {
        if (self.num_pages * node_per_page == self.num_objects) {
            const new_page = self.pa.getAdjacentPages(1) orelse return Error.MetadataNoMemory;
            self.initPage(page.pfn2phys(new_page));
        }
    }

    /// Initiate a new page to fill it with empty node list.
    /// Feeds the freelist with the new empty nodes.
    fn initPage(self: *PageStructCache, cache: VA) void {
        const ptr: [*]SlubPageNode = @ptrFromInt(cache);
        for (0..node_per_page) |i| {
            const empty_node: *EmptySlubPageNode = @ptrCast(&ptr[i]);
            empty_node.next = self.freelist;
            self.freelist = empty_node;
        }

        self.num_pages += 1;
    }
};

/// Single slub of the size.
const Slub = struct {
    const EmptyNode = packed struct {
        next: ?*EmptyNode,
    };

    /// The size of objects this slub can hold.
    size: usize,
    /// Number of objects that can be allocated in a page.
    objects_per_page: usize,

    /// Active page that can allocate at least one object.
    active_page: *SlubPageList.Node,
    /// List of pages that are not full excluding active_page.
    list_freepage: SlubPageList,
    /// List of pages that are full.
    list_fullpage: SlubPageList,
    /// Total number of allocated objects.
    num_objects: usize = 0,
    /// Total number of allocated pages.
    num_pages: usize = 0,

    /// Instantiate
    pub fn init(size: usize, page_cache: *PageStructCache, bpa: *BitmapPageAllocator) Error!Slub {
        const first_page_pfn = bpa.getAdjacentPages(1) orelse {
            return Error.NoMemory;
        };

        var slub = Slub{
            .size = size,
            .objects_per_page = page_size / size,
            .active_page = undefined,
            .list_freepage = .{},
            .list_fullpage = .{},
            .num_pages = 1,
        };
        slub.active_page = try slub.initSlubPage(page.pfn2phys(first_page_pfn), page_cache);

        return slub;
    }

    /// Allocate a slub object.
    pub fn alloc(self: *Slub, page_cache: *PageStructCache, bpa: *BitmapPageAllocator) Error![*]u8 {
        if (self.active_page.data.freelist == 0) {
            try self.swapActivePage(page_cache, bpa);
        }

        const object_to_use: *EmptyNode = @ptrFromInt(self.active_page.data.freelist);
        self.active_page.data.freelist = if (object_to_use.next) |o| @intFromPtr(o) else 0;
        self.num_objects += 1;

        return @ptrCast(object_to_use);
    }

    /// Free a slub object.
    pub fn free(self: *Slub, ptr: [*]u8) Error!void {
        const node: *EmptyNode = @alignCast(@ptrCast(ptr));
        node.next = @ptrFromInt(self.active_page.data.freelist);
        self.active_page.data.freelist = @intFromPtr(node);
        self.num_objects -= 1;

        // Find the page that contains the object.
        const object_page = @as(u64, @intFromPtr(node)) & ~arch.page_mask;
        if (self.active_page.data.addr == object_page) {
            // No need to do anything.
            return;
        }
        var page_ptr: ?*SlubPageList.Node = self.list_freepage.first;
        while (page_ptr != null) : (page_ptr = page_ptr.?.next) {
            if (page_ptr.?.data.addr == object_page) {
                // No need to do anything.
            }
        }
        page_ptr = self.list_fullpage.first;
        while (page_ptr != null) : (page_ptr = page_ptr.?.next) {
            if (page_ptr.?.data.addr == object_page) {
                // Move the page to the free list.
                self.list_fullpage.remove(page_ptr.?);
                self.list_freepage.append(page_ptr.?);
                return;
            }
        }

        // TODO: return empty page to the page allocator.

        @panic("free(): The slub object requested to free was not found in the slub.");
    }

    /// Initiate new page with empty nodes.
    fn initSlubPage(self: *Slub, slub_page: VA, page_cache: *PageStructCache) Error!*SlubPageList.Node {
        const pagelist_node = try page_cache.allocPageStruct();
        pagelist_node.data.addr = slub_page;
        pagelist_node.data.freelist = 0;
        pagelist_node.next = null;
        pagelist_node.prev = null;
        const pagedata = &pagelist_node.data;

        for (0..self.objects_per_page) |i| {
            const empty_node: *EmptyNode = @ptrFromInt(slub_page + i * self.size);
            empty_node.next = if (pagedata.freelist == 0) null else @ptrFromInt(pagedata.freelist);
            pagedata.freelist = @intFromPtr(empty_node);
        }

        return pagelist_node;
    }

    /// When there is no free object in the current active page,
    /// swap the active page with a free page.
    /// If there is no free pages, allocate a new page.
    fn swapActivePage(self: *Slub, page_cache: *PageStructCache, bpa: *BitmapPageAllocator) Error!void {
        if (self.active_page.data.freelist != 0) {
            @panic("mayAllocateNewPage() is called though there is a free object.");
        }

        // If there is no free pages, allocate a new page.
        if (self.list_freepage.first == null) {
            const new_page_pfn = bpa.getAdjacentPages(1) orelse return Error.NoMemory;
            const new_page_struct = try self.initSlubPage(page.pfn2phys(new_page_pfn), page_cache);
            self.list_freepage.append(new_page_struct);

            self.num_pages += 1;
        }

        // Here, it is guaranteed that there is at least one free page.
        const page_to_use = self.list_freepage.popFirst().?;
        self.list_fullpage.append(self.active_page);
        self.active_page = page_to_use;
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

const MockedPageAllocator = struct {
    pub fn getAdjacentPages(_: *MockedPageAllocator, n: usize) ?page.Pfn {
        if (n == 0) return null;

        const ret = std.c.mmap(
            null,
            page_size * n,
            std.os.linux.PROT.READ | std.os.linux.PROT.WRITE,
            .{
                .TYPE = std.os.linux.MAP_TYPE.PRIVATE,
                .ANONYMOUS = true,
            },
            -1,
            0,
        );
        return page.phys2pfn(@intFromPtr(ret));
    }

    pub fn returnAdjacentPages(_: *MockedPageAllocator, pfn: page.Pfn, n: usize) void {
        const ret = std.c.munmap(@ptrFromInt(page.pfn2phys(pfn)), page_size * n);
        if (ret != 0) unreachable;
    }
};

test "Initial state of slubs" {
    var page_allocator = MockedPageAllocator{};
    const arena = try Arena.init(&page_allocator);
    for (arena.slubs) |slub| {
        try testing.expectEqual(slub.active_page.data.addr & arch.page_mask, 0);
        try testing.expectEqual(slub.list_freepage.len, 0);
        try testing.expectEqual(slub.list_fullpage.len, 0);
    }

    const slub8 = &arena.slubs[0];
    try testing.expectEqual(slub8.objects_per_page, page_size / 8);
    try testing.expectEqual(slub8.num_pages, 1);
    try testing.expectEqual(slub8.num_objects, 0);
    const freelist = slub8.active_page.data.freelist;
    var len: usize = 0;
    var p: ?*Slub.EmptyNode = @ptrFromInt(freelist);
    while (p != null) : (p = p.?.next) {
        len += 1;
    }
    try testing.expectEqual(slub8.objects_per_page, len);

    const slub256 = &arena.slubs[7];
    const freelist256 = slub256.active_page.data.freelist;
    len = 0;
    p = @ptrFromInt(freelist256);
    while (p != null) : (p = p.?.next) {
        len += 1;
    }
    try testing.expectEqual(slub256.objects_per_page, len);
}

test "PageCache init" {
    var page_allocator = MockedPageAllocator{};
    const page_cache = try PageStructCache.init(&page_allocator);

    try testing.expectEqual(1, page_cache.num_pages);
    try testing.expectEqual(0, page_cache.num_objects);

    const freelist = page_cache.freelist;
    const node_size = PageStructCache.node_size;
    try testing.expectEqual(0x20, node_size);
    try testing.expectEqual(node_size, @intFromPtr(freelist.?) - @intFromPtr(freelist.?.next));

    var len: usize = 0;
    var p: ?*PageStructCache.EmptySlubPageNode = freelist;
    while (p != null) : (p = p.?.next) {
        len += 1;
    }
    try testing.expectEqual(PageStructCache.node_per_page, len);
}

test "PageCache Alloc/Free" {
    var page_allocator = MockedPageAllocator{};
    var page_cache = try PageStructCache.init(&page_allocator);
    var nodes = [_]*PageStructCache.SlubPageNode{undefined} ** PageStructCache.node_per_page;

    // Alloc
    for (0..PageStructCache.node_per_page) |i| {
        nodes[i] = try page_cache.allocPageStruct();
        if (i != 0) {
            try testing.expectEqual(0x20, @intFromPtr(nodes[i - 1]) - @intFromPtr(nodes[i]));
        }
    }
    try testing.expectEqual(1, page_cache.num_pages);
    try testing.expectEqual(PageStructCache.node_per_page, page_cache.num_objects);

    const lastone = try page_cache.allocPageStruct();
    try testing.expectEqual(2, page_cache.num_pages);
    try testing.expectEqual(PageStructCache.node_per_page + 1, page_cache.num_objects);

    // Free
    try page_cache.freePageStruct(lastone);
    try testing.expectEqual(PageStructCache.node_per_page, page_cache.num_objects);

    for (0..PageStructCache.node_per_page) |i| {
        try page_cache.freePageStruct(nodes[i]);
    }
    try testing.expectEqual(0, page_cache.num_objects);

    var len: usize = 0;
    var p: ?*PageStructCache.EmptySlubPageNode = page_cache.freelist;
    while (p != null) : (p = p.?.next) {
        len += 1;
    }
    try testing.expectEqual(PageStructCache.node_per_page * 2, len);
}

test "Slub" {
    var page_allocator = MockedPageAllocator{};
    var page_cache = try PageStructCache.init(&page_allocator);
    var arena = try Arena.init(&page_allocator);
    const slub512 = &arena.slubs[8];

    // Alloc one object.
    const obj1 = try slub512.alloc(&page_cache, &page_allocator);
    try testing.expectEqual(1, slub512.num_objects);
    try testing.expectEqual(1, slub512.num_pages);
    try testing.expectEqual(null, slub512.list_freepage.first);
    try testing.expectEqual(null, slub512.list_fullpage.first);

    // Alloc and fill one page with objects.
    for (0..slub512.objects_per_page - 1) |_| {
        _ = try slub512.alloc(&page_cache, &page_allocator);
    }
    try testing.expectEqual(slub512.objects_per_page, slub512.num_objects);
    try testing.expectEqual(1, slub512.num_pages);
    try testing.expectEqual(0, slub512.active_page.data.freelist);

    // Alloc one more object.
    const obj2 = try slub512.alloc(&page_cache, &page_allocator);
    try testing.expectEqual(slub512.objects_per_page + 1, slub512.num_objects);
    try testing.expectEqual(2, slub512.num_pages);
    try testing.expectEqual(0, slub512.list_freepage.len);
    try testing.expectEqual(1, slub512.list_fullpage.len);

    // Free two objects.
    try slub512.free(obj2);
    try slub512.free(obj1);
}

test "SlubAllocator" {
    var bpa = BitmapPageAllocator{};
    var slub_allocator = try SlubAllocator.init(&bpa);
    const alctr = slub_allocator.allocator();

    const obj1 = try alctr.alloc(u64, 1);
    try testing.expectEqual(1, slub_allocator.arena.slubs[0].num_objects);
    _ = try alctr.alloc(u64, 1);
    try testing.expectEqual(2, slub_allocator.arena.slubs[0].num_objects);

    try testing.expectEqual(0, slub_allocator.arena.slubs[1].num_objects);
    _ = try alctr.alloc(u64, 2);
    try testing.expectEqual(1, slub_allocator.arena.slubs[1].num_objects);
    _ = try alctr.alloc(u64, 2);
    _ = try alctr.alloc(u64, 2);
    try testing.expectEqual(3, slub_allocator.arena.slubs[1].num_objects);

    alctr.free(obj1);
    try testing.expectEqual(1, slub_allocator.arena.slubs[0].num_objects);
    alctr.free(obj1);
    try testing.expectEqual(0, slub_allocator.arena.slubs[0].num_objects);

    const obj_paged = try alctr.alloc(u8, page_size + 1);
    alctr.free(obj_paged);
}
