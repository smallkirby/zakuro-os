//! This file provides a mouse graphics.

const std = @import("std");
const log = std.log.scoped(.mouse);
const zakuro = @import("zakuro");
const gfx = zakuro.gfx;
const Vector = zakuro.Vector;
const colors = zakuro.color;
const MouseObserver = zakuro.drivers.usb.MouseObserver;

/// Interrupt number for a mouse device.
pub const intr_vector = 0x30;

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
    /// Maximum screen size.
    screen_size: Vector(u32),

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
                            pos.x + @as(i32, @bitCast(@as(u32, @truncate(x)))),
                            pos.y + @as(i32, @bitCast(@as(u32, @truncate(y)))),
                            colors.Black,
                        );
                    },
                    '.' => {
                        self.writer.writePixel(
                            pos.x + @as(i32, @bitCast(@as(u32, @truncate(x)))),
                            pos.y + @as(i32, @bitCast(@as(u32, @truncate(y)))),
                            colors.White,
                        );
                    },
                    else => {},
                }
            }
        }
    }

    /// Move the mouse cursor relative to the current position.
    pub fn moveRel(self: *Self, delta: Vector(i8)) void {
        self.eraseMouse();
        self.pos.x +|= @intCast(delta.x);
        self.pos.y +|= @intCast(delta.y);
        self.drawMouse();
    }

    fn adjustPos(self: *Self) void {
        self.pos.x = @max(0, @min(self.pos.x, self.screen_size));
        self.pos.y = @max(0, @min(self.pos.y, self.screen_size));
    }

    /// Erase mouse cursor by overwriting with the background color.
    fn eraseMouse(self: Self) void {
        for (0..mouse_cursor_height) |y| {
            for (0..mouse_cursor_width) |x| {
                if (mouse_shape[y][x] != ' ')
                    self.writer.writePixel(
                        self.pos.x +| gfx.usize2i32(x),
                        self.pos.y +| gfx.usize2i32(y),
                        self.ecolor,
                    );
            }
        }
    }
};
