//! This module provides the functionality of graphics output.

const zakuro = @import("zakuro");
const font = zakuro.font;
const colors = zakuro.color;
const Vector = zakuro.Vector;

pub const layer = @import("gfx/layer.zig");
pub const window = @import("gfx/window.zig");
pub const lib = @import("gfx/lib.zig");

/// Byte size of a pixel.
pub const bytes_per_pixel = 4;

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
    r: u8,
    g: u8,
    b: u8,

    pub fn eql(lhs: PixelColor, rhs: PixelColor) bool {
        return lhs.r == rhs.r and lhs.g == rhs.g and lhs.b == rhs.b;
    }
};

/// Primitive pixel writer to write a pixel color to the framebuffer.
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

    /// Write a pixel color to the frame buffer.
    pub fn writePixel(self: Self, x: u32, y: u32, color: PixelColor) void {
        if (x >= self.config.horizontal_resolution or
            y >= (self.config.vertical_resolution))
        {
            return;
        }

        self.write_pixel_func(
            self,
            @bitCast(x),
            @bitCast(y),
            color,
        );
    }

    /// Copy the memory from one framebuffer to that of this writer.
    pub fn memcpyFrameBuffer(self: Self, origin: Vector(u32), other: Self) void {
        const origin_x = origin.x;
        const origin_y = origin.y;

        for (0..other.config.vertical_resolution) |dy| {
            const dst = pixelAt(self.config, origin_x, origin_y + @as(u32, @truncate(dy)));
            const src = pixelAt(other.config, 0, @truncate(dy));
            @memcpy(dst, src[0 .. other.config.pixels_per_scan_line * bytes_per_pixel]);
        }
    }

    /// Copy a rectangle inside the framebuffer to the specified position.
    pub fn copyRectangle(self: Self, dst: Vector(u32), src: Vector(u32), size: Vector(u32)) void {
        for (0..size.y) |dy| {
            const d = pixelAt(self.config, dst.x, dst.y + @as(u32, @truncate(dy)));
            const s = pixelAt(self.config, src.x, src.y + @as(u32, @truncate(dy)));
            @memcpy(d, s[0 .. size.x * bytes_per_pixel]);
        }
    }

    /// Write a pixel color to the specified position in RGB format.
    fn writePixelRgb(self: Self, x: u32, y: u32, color: PixelColor) void {
        const addr = pixelAt(self.config, x, y);
        addr[0] = color.r;
        addr[1] = color.g;
        addr[2] = color.b;
    }

    /// Write a pixel color to the specified position in BGR format.
    fn writePixelBgr(self: Self, x: u32, y: u32, color: PixelColor) void {
        const addr = pixelAt(self.config, x, y);
        addr[0] = color.b;
        addr[1] = color.g;
        addr[2] = color.r;
    }

    /// Get the address of the framebuffer at the specified pixel.
    /// Note that this function does not perform bounds checking.
    inline fn pixelAt(config: *FrameBufferConfig, x: u32, y: u32) [*]u8 {
        const rel_pos = config.pixels_per_scan_line *| y +| x;
        return @ptrCast(&config.frame_buffer[rel_pos *| bytes_per_pixel]);
    }
};
