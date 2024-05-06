//! This module provides the functionality of graphics output.

const zakuro = @import("zakuro");
const font = zakuro.font;
const colors = zakuro.color;

/// 2D vector.
pub fn Vector(comptime T: type) type {
    return struct {
        x: T,
        y: T,
    };
}

/// Pixel data format defined by UEFI.
pub const PixelFormat = enum(u8) {
    PixelRGBResv8BitPerColor,
    PixelBGRResv8BitPerColor,
};

/// Configuration to describe the framebuffer.
pub const FrameBufferConfig = extern struct {
    frame_buffer: [*]u8,
    pixels_per_scan_line: u32,
    horizontal_resolution: u32,
    vertical_resolution: u32,
    pixel_format: PixelFormat,
};

/// Represents a pixel RGB color.
pub const PixelColor = struct {
    red: u8,
    green: u8,
    blue: u8,
};

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

/// Pixel writer to write a pixel color to the framebuffer.
pub const PixelWriter = struct {
    config: *FrameBufferConfig,
    write_pixel_func: *const fn (Self, u32, u32, PixelColor) void,

    const Self = @This();

    pub fn new(config: *FrameBufferConfig) PixelWriter {
        return PixelWriter{
            .config = config,
            .write_pixel_func = switch (config.pixel_format) {
                .PixelRGBResv8BitPerColor => &writePixelRgb,
                .PixelBGRResv8BitPerColor => &writePixelBgr,
            },
        };
    }

    /// Write an ASCII character to the specified position.
    pub fn writeAscii(self: Self, x: u32, y: u32, c: u8, color: PixelColor) void {
        const fonts = font.getFont(c).?;
        for (0..font.FONT_HEIGHT) |dy| {
            for (0..font.FONT_WIDTH) |dx| {
                if ((fonts[dy] << @truncate(dx)) & 0x80 != 0) {
                    const px = @as(u32, @truncate(dx)) + x;
                    const py = @as(u32, @truncate(dy)) + y;
                    self.writePixel(px, py, color);
                }
            }
        }
    }

    /// Write a string to the specified position until null character.
    pub fn writeString(self: Self, x: u32, y: u32, s: []const u8, color: PixelColor) void {
        var px = x;
        var py = y;
        for (s) |c| {
            if (c == 0) break;
            if (c == '\n') {
                px = x;
                py += @truncate(font.FONT_HEIGHT);
            } else {
                self.writeAscii(px, py, c, color);
                px += @truncate(font.FONT_WIDTH);
            }
        }
    }

    /// Write a pixel color to the specified position.
    pub fn writePixel(self: Self, x: u32, y: u32, color: PixelColor) void {
        return self.write_pixel_func(self, x, y, color);
    }

    /// Draw a rectangle with the specified position, size, and color.
    /// The only edge of the rectangle is drawn.
    pub fn drawRectangle(
        self: Self,
        pos: Vector(u32),
        size: Vector(u32),
        color: PixelColor,
    ) void {
        for (0..size.x) |dx| {
            self.writePixel(size.x + @as(u32, @truncate(dx)), pos.y, color);
        }
    }

    /// Fill a rectangle with the specified position, size, and color.
    pub fn fillRectangle(
        self: Self,
        pos: Vector(u32),
        size: Vector(u32),
        color: PixelColor,
    ) void {
        for (0..size.y) |dy| {
            for (0..size.x) |dx| {
                self.writePixel(
                    pos.x + @as(u32, @truncate(dx)),
                    pos.y + @as(u32, @truncate(dy)),
                    color,
                );
            }
        }
    }

    /// Draw a mouse cursor at the specified position.
    pub fn drawMouse(self: Self, pos: Vector(u32)) void {
        for (0..mouse_cursor_height) |y| {
            for (0..mouse_cursor_width) |x| {
                switch (mouse_shape[y][x]) {
                    '@' => {
                        self.writePixel(
                            @truncate(pos.x + x),
                            @truncate(pos.y + y),
                            colors.Black,
                        );
                    },
                    '.' => {
                        self.writePixel(
                            @truncate(pos.x + x),
                            @truncate(pos.y + y),
                            colors.White,
                        );
                    },
                    else => {},
                }
            }
        }
    }

    /// Write a pixel color to the specified position in RGB format.
    fn writePixelRgb(self: Self, x: u32, y: u32, color: PixelColor) void {
        const addr = pixelAt(self.config, x, y);
        addr[0] = color.red;
        addr[1] = color.green;
        addr[2] = color.blue;
    }

    /// Write a pixel color to the specified position in BGR format.
    fn writePixelBgr(self: Self, x: u32, y: u32, color: PixelColor) void {
        const addr = pixelAt(self.config, x, y);
        addr[0] = color.blue;
        addr[1] = color.green;
        addr[2] = color.red;
    }

    /// Get the address of the framebuffer at the specified pixel.
    /// Note that this function does not perform bounds checking.
    fn pixelAt(config: *FrameBufferConfig, x: u32, y: u32) [*]u8 {
        const rel_pos = config.pixels_per_scan_line * y + x;
        return @ptrCast(&config.frame_buffer[rel_pos * 4]);
    }
};
