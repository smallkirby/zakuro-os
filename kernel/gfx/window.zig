//! This file defines windows used in a layerd graphics system.

const std = @import("std");
const log = std.log.scoped(.window);
const Allocator = std.mem.Allocator;

const zakuro = @import("zakuro");
const gfx = zakuro.gfx;
const Pos = zakuro.Vector(i32);

pub const WindowError = error{
    /// Memory allocation failed.
    NoMemory,
};
const Error = WindowError;

/// Windows is a rectangle in a layer.
/// Layers have a infinite size, but windows have a fixed size.
pub const Window = struct {
    const Self = @This();

    /// Width in pixels of this window.
    width: usize,
    /// Height in pixels of this window.
    height: usize,
    /// Transparent color of this window.
    /// If a pixel has this color in this window, the pixel is not drawn.
    transparent_color: ?gfx.PixelColor = null,
    /// Pixel data of this window.
    data: [][]gfx.PixelColor,
    /// Memory allocator used to allocate an pixel buffer.
    allocator: Allocator,

    /// Initialize the window.
    /// Caller MUST ensure to call `deinit` to free the allocated memory.
    pub fn init(width: usize, height: usize, allocator: Allocator) Error!Self {
        var data = allocator.alloc([]gfx.PixelColor, height) catch return Error.NoMemory;
        for (0..height) |y| {
            data[y] = allocator.alloc(gfx.PixelColor, width) catch return Error.NoMemory;
        }

        return Self{
            .width = width,
            .height = height,
            .data = data,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: Self) void {
        self.allocator.free(self.data);
    }

    /// Draw the window at the specified position.
    pub fn drawAt(self: *Self, pos: Pos, writer: gfx.PixelWriter) void {
        for (0..self.height) |dy| {
            for (0..self.width) |dx| {
                const c = self.at(dx, dy);
                if (self.transparent_color != null and gfx.PixelColor.eql(c, self.transparent_color))
                    continue;
                writer.writePixel(pos.x + dx, pos.y + dy, self.data[dy][dx]);
            }
        }
    }

    /// Get a pixel color at the specified position.
    inline fn at(self: *Self, x: i32, y: i32) gfx.PixelColor {
        return self.data[y][x];
    }
};
