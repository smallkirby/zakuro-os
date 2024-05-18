//! This file provides a mouse graphics.

const std = @import("std");
const zakuro = @import("zakuro");
const gfx = zakuro.graphics;
const Vector = zakuro.Vector;
const colors = zakuro.color;
const MouseObserver = zakuro.drivers.usb.MouseObserver;

/// Width of the mouse cursor.
const mouse_cursor_width = 12;
/// Height of the mouse cursor.
const mouse_cursor_height = 21;
/// Mouse cursor shape data.
const mouse_shape = [mouse_cursor_height]*const [mouse_cursor_width:0]u8{
    ".           ",
    "..          ",
    ".@.         ",
    ".@@.        ",
    ".@@@.       ",
    ".@@@@.      ",
    ".@@@@@.     ",
    ".@@@@@@.    ",
    ".@@@@@@@.   ",
    ".@@@@@@@@.  ",
    ".@@@@@@@@@. ",
    ".@@@@@@@....",
    ".@@@@@@@.   ",
    ".@@@@@@.    ",
    ".@@@.@@.    ",
    ".@@..@@@.   ",
    ".@. .@@@.   ",
    "..   .@@@.  ",
    ".    .@@@.  ",
    "      .@@.  ",
    "       ...  ",
};

/// Mouse cursor.
pub const MouseCursor = struct {
    /// Pixel Writer
    writer: *const gfx.PixelWriter,
    /// Position of the mouse cursor.
    pos: Vector(i32),
    /// Color used to erase the mouse cursor.
    ecolor: gfx.PixelColor,

    const Self = @This();

    /// Get a mouse observer for the mouse movement.
    pub fn observer(self: *Self) MouseObserver {
        return .{
            .ptr = self,
            .vtable = .{
                .onMove = vtMoveRel,
            },
        };
    }

    fn vtMoveRel(ctx: *anyopaque, delta_x: i8, delta_y: i8) void {
        const self: *Self = @alignCast(@ptrCast(ctx));
        self.moveRel(.{ .x = delta_x, .y = delta_y });
    }

    /// Draw a mouse cursor at the specified position.
    pub fn drawMouse(self: Self) void {
        const pos = self.pos;
        for (0..mouse_cursor_height) |y| {
            for (0..mouse_cursor_width) |x| {
                switch (mouse_shape[y][x]) {
                    '@' => {
                        self.writer.writePixel(
                            @as(u32, @bitCast(pos.x)) + @as(u32, @truncate(x)),
                            @as(u32, @bitCast(pos.y)) + @as(u32, @truncate(y)),
                            colors.Black,
                        );
                    },
                    '.' => {
                        self.writer.writePixel(
                            @as(u32, @bitCast(pos.x)) + @as(u32, @truncate(x)),
                            @as(u32, @bitCast(pos.y)) + @as(u32, @truncate(y)),
                            colors.White,
                        );
                    },
                    else => {},
                }
            }
        }
    }

    /// Move the mouse cursor relative to the current position.
    pub fn moveRel(self: *Self, delta: Vector(i32)) void {
        self.eraseMouse();
        self.pos.x +|= delta.x;
        self.pos.y +|= delta.y;
        self.drawMouse();
    }

    /// Erase mouse cursor by overwriting with the background color.
    fn eraseMouse(self: Self) void {
        for (0..mouse_cursor_height) |y| {
            for (0..mouse_cursor_width) |x| {
                if (mouse_shape[y][x] != ' ')
                    self.writer.writePixel(
                        @as(u32, @bitCast(self.pos.x)) +| @as(u32, @truncate(x)),
                        @as(u32, @bitCast(self.pos.y)) +| @as(u32, @truncate(y)),
                        self.ecolor,
                    );
            }
        }
    }
};
