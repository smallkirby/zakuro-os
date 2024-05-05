//! This module provides a graphic console.

const graphics = @import("graphics.zig");
const PixelWriter = graphics.PixelWriter;
const PixelColor = graphics.PixelColor;
const std = @import("std");
const log = std.log.scoped(.console);
const format = std.fmt.format;

const ConsoleError = error{};
const ConsoleContext = struct {
    console: *Console,
};
const ConsoleWriter = std.io.Writer(
    ConsoleContext,
    ConsoleError,
    Console.write,
);

/// Graphic console.
/// Do NOT edit any fields directly.
pub const Console = struct {
    /// The number of rows in the console.
    const kRows: u32 = 25;
    /// The number of columns in the console.
    const kCols: u32 = 80;

    const Self = @This();

    /// Writer to write to.
    writer: PixelWriter,
    /// Foreground color.
    fgc: PixelColor,
    /// Background color.
    bgc: PixelColor,
    /// Cursor column.
    cur_col: u32 = 0,
    /// Cursor row.
    cur_row: u32 = 0,
    /// Console buffer
    buffer: [kRows][kCols + 1]u8,

    /// Initialize a new console with specified fg/bg colors.
    pub fn new(writer: PixelWriter, fgc: PixelColor, bgc: PixelColor) Self {
        return Self{
            .writer = writer,
            .fgc = fgc,
            .bgc = bgc,
            .buffer = std.mem.zeroes([kRows][kCols + 1]u8),
        };
    }

    fn write(context: ConsoleContext, bytes: []const u8) ConsoleError!usize {
        const self = context.console;
        for (bytes) |c| {
            if (c == '\n') {
                self.newline();
            } else {
                self.writer.writeAscii(8 * self.cur_col, 16 * self.cur_row, c, self.fgc);
                self.buffer[self.cur_row][self.cur_col] = c;
                self.cur_col += 1;
            }
        }

        return bytes.len;
    }

    /// Print an ascii message to the console.
    pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) void {
        format(ConsoleWriter{ .context = .{ .console = self } }, fmt, args) catch unreachable;
    }

    fn newline(self: *Self) void {
        self.cur_col = 0;

        if (self.cur_row < kRows - 1) {
            self.cur_row += 1;
        } else {
            // Clean the console.
            for (0..16 * kRows) |y| {
                for (0..8 * kCols) |x| {
                    self.writer.writePixel(@truncate(x), @truncate(y), self.bgc);
                }
            }
            // Scroll up.
            for (0..kRows - 1) |row| {
                @memcpy(&self.buffer[row], &self.buffer[row + 1]);
                self.writer.writeString(0, @truncate(16 * row), &self.buffer[row], self.fgc);
            }
        }
    }
};
