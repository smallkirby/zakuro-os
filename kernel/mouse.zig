//! This file provides a mouse graphics.

const std = @import("std");
const log = std.log.scoped(.mouse);
const zakuro = @import("zakuro");
const gfx = zakuro.gfx;
const Vector = zakuro.Vector;
const colors = zakuro.color;
const MouseObserver = zakuro.drivers.usb.MouseObserver;
const getLayers = gfx.layer.getLayers();

/// Interrupt number for a mouse device.
pub const intr_vector = 0x30;

/// Width of the mouse cursor.
pub const mouse_cursor_width = 12;
/// Height of the mouse cursor.
pub const mouse_cursor_height = 21;
pub const mouse_transparent_color = colors.Blue;
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
    /// Window to draw the mouse cursor.
    window: *gfx.window.Window,
    /// Color used to erase the mouse cursor.
    ecolor: gfx.PixelColor,
    /// Screen size.
    screen_size: zakuro.Vector(u32),

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
        for (0..mouse_cursor_height) |y| {
            for (0..mouse_cursor_width) |x| {
                const color = switch (mouse_shape[y][x]) {
                    '@' => colors.Black,
                    '.' => colors.White,
                    ' ' => mouse_transparent_color,
                    else => unreachable,
                };
                self.window.writeAt(.{
                    .x = @as(u32, @truncate(x)),
                    .y = @as(u32, @truncate(y)),
                }, color);
            }
        }
    }

    /// Move the mouse cursor relative to the current position.
    pub fn moveRel(self: *Self, delta: Vector(i8)) void {
        var x: i32 = @bitCast(self.window.origin.x);
        var y: i32 = @bitCast(self.window.origin.y);
        x +|= @intCast(delta.x);
        y +|= @intCast(delta.y);
        if (x < 0) x = 0;
        if (y < 0) y = 0;
        if (x + 1 >= self.screen_size.x) x = @as(i32, @bitCast(self.screen_size.x)) - 1;
        if (y + 1 >= self.screen_size.y) y = @as(i32, @bitCast(self.screen_size.y)) - 1;
        self.window.moveOrigin(.{
            .x = @bitCast(x),
            .y = @bitCast(y),
        });

        self.drawMouse();
        gfx.layer.getLayers().flush();
    }

    /// Erase mouse cursor by overwriting with the background color.
    fn eraseMouse(self: Self) void {
        for (0..mouse_cursor_height) |y| {
            for (0..mouse_cursor_width) |x| {
                if (mouse_shape[y][x] != ' ')
                    self.window.writeAt(
                        .{
                            .x = self.pos.x +| @as(u32, @truncate(x)),
                            .y = self.pos.y +| @as(u32, @truncate(y)),
                        },
                        self.ecolor,
                    );
            }
        }
    }
};
