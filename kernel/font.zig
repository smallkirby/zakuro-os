//! This module provides a simple set of ascii fonts
//! each of which consists of 16x8 pixels.

pub const font_height: usize = 16;
pub const font_width: usize = 8;

const fonts = @extern(*[0x100][16]u8, .{
    .name = "_binary_fontdata_start",
    .linkage = .strong,
});
const _fonts_len_raw = @extern(*u32, .{
    .name = "_binary_fontdata_size",
    .linkage = .strong,
});

/// Get 16x8 pixel font data for a given ascii character.
/// Returns null if the character is not supported.
pub fn getFont(char: u8) ?[16]u8 {
    if (@as(usize, char) >= @intFromPtr(_fonts_len_raw)) {
        return null;
    }
    return fonts[char];
}
