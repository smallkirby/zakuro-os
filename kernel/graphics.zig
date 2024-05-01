//! This module provides the functionality of graphics output.

const font = @import("font.zig");

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

/// Pixel writer to write a pixel color to the framebuffer.
pub const PixelWriter = struct {
    config: *FrameBufferConfig,
    write_pixel_func: *const fn (Self, u32, u32, PixelColor) void,

    const Self = @This();

    pub fn new(config: *FrameBufferConfig) PixelWriter {
        return PixelWriter{
            .config = config,
            .write_pixel_func = switch (config.pixel_format) {
                .PixelRGBResv8BitPerColor => &write_pixel_rgb,
                .PixelBGRResv8BitPerColor => &write_pixel_bgr,
            },
        };
    }

    /// Write an ASCII character to the specified position.
    pub fn write_ascii(self: Self, x: u32, y: u32, c: u8, color: PixelColor) !void {
        const fonts = font.get_font(c).?;
        for (0..font.FONT_HEIGHT) |dy| {
            for (0..font.FONT_WIDTH) |dx| {
                if ((fonts[dy] << @truncate(dx)) & 0x80 != 0) {
                    const px = @as(u32, @truncate(dx)) + x;
                    const py = @as(u32, @truncate(dy)) + y;
                    self.write_pixel(px, py, color);
                }
            }
        }
    }

    /// Write a string to the specified position until null character.
    pub fn write_string(self: Self, x: u32, y: u32, s: []const u8, color: PixelColor) !void {
        var px = x;
        var py = y;
        for (s) |c| {
            if (c == 0) break;
            if (c == '\n') {
                px = x;
                py += @truncate(font.FONT_HEIGHT);
            } else {
                try self.write_ascii(px, py, c, color);
                px += @truncate(font.FONT_WIDTH);
            }
        }
    }

    /// Write a pixel color to the specified position.
    pub fn write_pixel(self: Self, x: u32, y: u32, color: PixelColor) void {
        return self.write_pixel_func(self, x, y, color);
    }

    /// Write a pixel color to the specified position in RGB format.
    fn write_pixel_rgb(self: Self, x: u32, y: u32, color: PixelColor) void {
        const addr = pixel_at(self.config, x, y);
        addr[0] = color.red;
        addr[1] = color.green;
        addr[2] = color.blue;
    }

    /// Write a pixel color to the specified position in BGR format.
    fn write_pixel_bgr(self: Self, x: u32, y: u32, color: PixelColor) void {
        const addr = pixel_at(self.config, x, y);
        addr[0] = color.blue;
        addr[1] = color.green;
        addr[2] = color.red;
    }

    /// Get the address of the framebuffer at the specified pixel.
    /// Note that this function does not perform bounds checking.
    fn pixel_at(config: *FrameBufferConfig, x: u32, y: u32) [*]u8 {
        const rel_pos = config.pixels_per_scan_line * y + x;
        return @ptrCast(&config.frame_buffer[rel_pos * 4]);
    }
};
