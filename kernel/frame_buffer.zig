//! This module provides definitions of framebuffer structures.

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

/// Get the address of the framebuffer at the specified pixel.
/// Note that this function does not perform bounds checking.
pub fn pixel_at(config: *FrameBufferConfig, x: u32, y: u32) [*]u8 {
    const rel_pos = config.pixels_per_scan_line * y + x;
    return @ptrCast(&config.frame_buffer[rel_pos * 4]);
}

/// Write a pixel color to the specified position.
/// TODO: Can we use a function pointer and struct to avoid repeated switch even in baremetal?
pub fn write_pixel(config: *FrameBufferConfig, x: u32, y: u32, color: PixelColor) void {
    switch (config.pixel_format) {
        .PixelRGBResv8BitPerColor => write_pixel_rgb(config, x, y, color),
        .PixelBGRResv8BitPerColor => write_pixel_bgr(config, x, y, color),
    }
}

/// Write a pixel color to the specified position in RGB format.
fn write_pixel_rgb(config: *FrameBufferConfig, x: u32, y: u32, color: PixelColor) void {
    const addr = pixel_at(config, x, y);
    addr[0] = color.red;
    addr[1] = color.green;
    addr[2] = color.blue;
}

/// Write a pixel color to the specified position in BGR format.
fn write_pixel_bgr(config: *FrameBufferConfig, x: u32, y: u32, color: PixelColor) void {
    const addr = pixel_at(config, x, y);
    addr[0] = color.blue;
    addr[1] = color.green;
    addr[2] = color.red;
}
