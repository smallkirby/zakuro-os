//! This module provides a simple set of ascii fonts
//! each of which consists of 16x8 pixels.

pub const FONT_HEIGHT: usize = 16;
pub const FONT_WIDTH: usize = 8;

const fonts = @extern(*[0x100][16]u8, .{
    .name = "_binary_fontdata_start",
    .linkage = .strong,
});
const _fonts_len_raw = @extern(*u32, .{
    .name = "_binary_fontdata_size",
    .linkage = .strong,
});

pub fn get_font(char: u8) ?[16]u8 {
    if (@as(usize, char) >= @intFromPtr(_fonts_len_raw)) {
        return null;
    }
    return fonts[char];
}
