//! This file defines windows used in a layerd graphics system.

const std = @import("std");
const log = std.log.scoped(.window);
const Allocator = std.mem.Allocator;

const zakuro = @import("zakuro");
const gfx = zakuro.gfx;
const Pos = zakuro.Vector(u32);
const PixelColor = gfx.PixelColor;
const font = zakuro.font;

pub const WindowError = error{
    /// Memory allocation failed.
    NoMemory,
};
const Error = WindowError;

/// Windows is a graphical rectangle region.
/// It have its buffer. To render it on a screen, you have to explicitly flush it.
pub const Window = struct {
    const Self = @This();

    /// Window ID
    id: usize,
    /// Width in pixels of this window.
    width: u32,
    /// Height in pixels of this window.
    height: u32,
    /// Origin of this window.
    origin: Pos,
    /// Transparent color of this window.
    /// If a pixel has this color in this window, the pixel is not drawn.
    transparent_color: ?gfx.PixelColor = null,
    /// Visibility of this window.
    visible: bool = true,
    /// Pixel data of this window.
    data: [][]gfx.PixelColor,
    /// Memory allocator used to allocate an pixel buffer.
    allocator: Allocator,
    /// Writer to the shadow buffer of the frame buffer.
    /// Converting PixelColor to u8 for every pixels in a window every time window is refreshed is too expensive.
    /// Therefore, we use a shadow buffer and copy the content using memory copy when the window was flushed.
    /// When the content in a windows is not changed, pixel conversion is not performed.
    shadow_writer: gfx.PixelWriter,

    /// Initialize the window.
    /// Caller MUST ensure to call `deinit` to free the allocated memory.
    pub fn init(
        id: usize,
        width: u32,
        height: u32,
        fb_config: gfx.FrameBufferConfig,
        allocator: Allocator,
    ) Error!Self {
        var data = allocator.alloc([]gfx.PixelColor, height) catch return Error.NoMemory;
        for (0..height) |y| {
            data[y] = allocator.alloc(gfx.PixelColor, width) catch return Error.NoMemory;
        }

        const shadow_buffer = allocator.alloc(u8, width * height * 4) catch return Error.NoMemory;
        const config = allocator.create(gfx.FrameBufferConfig) catch return Error.NoMemory;
        config.frame_buffer = @ptrCast(shadow_buffer.ptr);
        config.pixel_format = fb_config.pixel_format;
        config.horizontal_resolution = width;
        config.vertical_resolution = height;
        config.pixels_per_scan_line = width;

        return Self{
            .id = id,
            .width = width,
            .height = height,
            .data = data,
            .origin = .{ .x = 0, .y = 0 },
            .allocator = allocator,
            .shadow_writer = gfx.PixelWriter.new(config),
        };
    }

    pub fn deinit(self: Self) void {
        self.allocator.free(self.data);
        self.allocator.free(self.shadow_writer.config.frame_buffer);
    }

    /// Write a pixel color at the specified position.
    /// This function just writes the pixel color to the buffer.
    /// You have to flush the buffer to the screen.
    pub fn writeAt(self: Self, pos: Pos, color: gfx.PixelColor) void {
        self.data[pos.y][pos.x] = color;
        self.shadow_writer.writePixel(pos.x, pos.y, color);
    }

    /// Draw the buffer in the window at the origin.
    pub fn flush(self: Self, writer: gfx.PixelWriter) void {
        // If the window is invisible, do nothing.
        if (!self.visible) return;

        if (self.transparent_color) |tc| {
            for (0..self.height) |dy| {
                // If the transparent color is set, flush each pixel one by one.
                for (0..self.width) |dx| {
                    const c = self.at(dx, dy);
                    if (gfx.PixelColor.eql(c, tc))
                        continue;
                    writer.writePixel(
                        self.origin.x + @as(u32, @truncate(dx)),
                        self.origin.y + @as(u32, @truncate(dy)),
                        self.data[dy][dx],
                    );
                }
            }
        } else {
            // If the transparent color is not set, flush the whole line at once.
            writer.memcpyFrameBuffer(self.origin, self.shadow_writer);
        }
    }

    /// Write an ASCII character to the specified position.
    pub fn writeAscii(self: Self, x: u32, y: u32, c: u8, fgc: PixelColor, bgc: PixelColor) void {
        const fonts = font.getFont(c).?;
        for (0..font.FONT_HEIGHT) |dy| {
            for (0..font.FONT_WIDTH) |dx| {
                const px = @as(u32, @truncate(dx)) + x;
                const py = @as(u32, @truncate(dy)) + y;
                if ((fonts[dy] << @truncate(dx)) & 0x80 != 0) {
                    self.writeAt(.{ .x = px, .y = py }, fgc);
                } else {
                    self.writeAt(.{ .x = px, .y = py }, bgc);
                }
            }
        }
    }

    /// Fill a rectangle with the specified position, size, and color.
    pub fn fillRectangle(self: Self, pos: Pos, size: Pos, color: PixelColor) void {
        for (0..size.y) |dy| {
            for (0..size.x) |dx| {
                self.writeAt(
                    .{
                        .x = pos.x + @as(u32, @truncate(dx)),
                        .y = pos.y + @as(u32, @truncate(dy)),
                    },
                    color,
                );
            }
        }
    }

    /// Draw a rectangle with the specified position, size, and color.
    /// The only edge of the rectangle is drawn.
    pub fn drawRectangle(self: Self, pos: Pos, size: Pos, color: PixelColor) void {
        for (0..size.x) |dx| {
            self.writeAt(
                .{ .x = pos.x + @as(u32, @truncate(dx)), .y = pos.y },
                color,
            );
            self.writeAt(
                .{ .x = pos.x + @as(u32, @truncate(dx)), .y = pos.y + (size.y - 1) },
                color,
            );
        }
        for (0..size.y) |dy| {
            self.writeAt(
                .{ .x = pos.x, .y = pos.y + @as(u32, @truncate(dy)) },
                color,
            );
            self.writeAt(
                .{ .x = pos.x + (size.x - 1), .y = pos.y + @as(u32, @truncate(dy)) },
                color,
            );
        }
    }

    /// Write a string to the specified position until null character.
    pub fn writeString(self: Self, pos: Pos, s: []const u8, fgc: PixelColor, bgc: PixelColor) void {
        var px = pos.x;
        var py = pos.y;
        for (s) |c| {
            if (c == 0) break;
            if (c == '\n') {
                px = pos.x;
                py += @intCast(font.FONT_HEIGHT);
            } else {
                self.writeAscii(px, py, c, fgc, bgc);
                px += @intCast(font.FONT_WIDTH);
            }
        }
    }

    /// Move the origin of this window.
    pub fn moveOrigin(self: *Self, pos: Pos) void {
        self.origin = pos;
    }

    /// Move the origin of this window relatively.
    pub fn moveOriginRel(self: *Self, delta: zakuro.Vector(i32)) void {
        var x: i32 = @bitCast(self.origin.x);
        var y: i32 = @bitCast(self.origin.y);
        x +|= delta.x;
        y +|= delta.y;
        if (x < 0) x = 0;
        if (y < 0) y = 0;
        self.origin = .{
            .x = @bitCast(x),
            .y = @bitCast(y),
        };
    }

    /// Get a pixel color at the specified position.
    inline fn at(self: Self, x: usize, y: usize) gfx.PixelColor {
        return self.data[y][x];
    }
};
