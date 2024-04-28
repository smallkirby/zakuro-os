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
