//! This module defines a set of colors.

const Color = @import("gfx.zig").PixelColor;

fn c(red: u8, green: u8, blue: u8) Color {
    return .{ .red = red, .green = green, .blue = blue };
}

pub const Red = c(0xFF, 0x00, 0x00);
pub const Green = c(0x00, 0xFF, 0x00);
pub const Blue = c(0x00, 0x00, 0xFF);
pub const White = c(0xFF, 0xFF, 0xFF);
pub const Black = c(0x00, 0x00, 0x00);

pub const LightPurple = c(0x52, 0x0A, 0x2C);
pub const DarkPurple = c(0x28, 0x0C, 0x1C);

pub const GBBg = c(0x28, 0x28, 0x28);
pub const GBFg = c(0xEB, 0xDB, 0xB2);
