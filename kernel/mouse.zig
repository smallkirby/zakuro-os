//! This file provides a mouse graphics.

const std = @import("std");
const log = std.log.scoped(.mouse);
const Allocator = std.mem.Allocator;

const zakuro = @import("zakuro");
const gfx = zakuro.gfx;
const Vector = zakuro.Vector;
const colors = zakuro.color;
const event = zakuro.event;
const MouseObserver = zakuro.drivers.usb.MouseObserver;
const getLayers = gfx.layer.getLayers();

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
    /// Previous button state.
    prev_btn: ButtonState = std.mem.zeroInit(ButtonState, .{}),
    /// Window that is being dragged.
    win_in_drag: ?*gfx.window.Window = null,

    /// Main color of the mouse cursor.
    mainc: gfx.PixelColor = colors.Black,
    /// Frame color of the mouse cursor.
    framec: gfx.PixelColor = colors.White,

    const Self = @This();

    /// Get a mouse observer for the mouse movement.
    pub fn observer(self: *Self, allocator: Allocator) !*MouseObserver {
        const ret = try allocator.create(MouseObserver);
        ret.* = .{
            .ptr = self,
            .vtable = .{
                .onMove = vtMoveRel,
            },
        };

        return ret;
    }

    fn vtMoveRel(ctx: *anyopaque, btn: u8, delta_x: i8, delta_y: i8) void {
        const self: *Self = @alignCast(@ptrCast(ctx));
        self.moveRel(
            @bitCast(btn),
            .{ .x = delta_x, .y = delta_y },
        );
    }

    /// Draw a mouse cursor at the specified position.
    pub fn drawMouse(self: Self) void {
        for (0..mouse_cursor_height) |y| {
            for (0..mouse_cursor_width) |x| {
                const color = switch (mouse_shape[y][x]) {
                    '@' => self.mainc,
                    '.' => self.framec,
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
    pub fn moveRel(self: *Self, btn: ButtonState, delta: Vector(i8)) void {
        // Move mouse window.
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

        // Drag window on click.
        const prev_left_pressed = self.prev_btn.left_pressed;
        if (!prev_left_pressed and btn.left_pressed) {
            self.framec = colors.Red;
            if (getLayers.findLayerByPosition(self.window.origin, self.window.id)) |window| {
                self.win_in_drag = window;
            }
        } else if (self.prev_btn.left_pressed and btn.left_pressed) {
            if (self.win_in_drag) |window| {
                window.moveOriginRel(.{
                    .x = @intCast(delta.x),
                    .y = @intCast(delta.y),
                });
            }
        } else if (prev_left_pressed and !btn.left_pressed) {
            self.framec = colors.White;
            self.win_in_drag = null;
        }

        // Flush the mouse.
        self.prev_btn = btn;
        self.drawMouse();
        gfx.layer.getLayers().flush(); // Flush all layers to erase the mouse cursor.
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

const ButtonState = packed struct(u8) {
    left_pressed: bool,
    right_pressed: bool,
    _reserved: u6,
};

pub const MouseEvent = struct {
    mouse: *MouseCursor,
    btn: ButtonState,
    delta_x: i8,
    delta_y: i8,
};
