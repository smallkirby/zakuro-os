//! This module provides a graphic console.

const std = @import("std");
const log = std.log.scoped(.console);
const format = std.fmt.format;

const zakuro = @import("zakuro");
const gfx = zakuro.gfx;
const PixelWriter = gfx.PixelWriter;
const PixelColor = gfx.PixelColor;
const Window = gfx.window.Window;
const colors = zakuro.color;

const ConsoleError = error{};
pub const ConsoleContext = struct {
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
    window: *Window,
    /// Default foreground color.
    fgc: PixelColor,
    /// Default background color.
    bgc: PixelColor,
    /// Current foreground color.
    cur_fgc: PixelColor,
    /// Current background color.
    cur_bgc: PixelColor,
    /// Cursor column.
    cur_col: u32 = 0,
    /// Cursor row.
    cur_row: u32 = 0,
    /// Terminal color parser.
    term_parser: TermParser,

    /// Initialize a new console with specified fg/bg colors.
    pub fn new(window: *Window, fgc: PixelColor, bgc: PixelColor) Self {
        var self = Self{
            .window = window,
            .fgc = fgc,
            .bgc = bgc,
            .cur_fgc = fgc,
            .cur_bgc = bgc,
            .term_parser = TermParser.new(),
        };
        self.clear();

        return self;
    }

    // TODO: current implementation strips terminal color codes and saves them to the buffer.
    //   Therefore, they lose their styles after scrolled up.
    pub fn write(context: ConsoleContext, bytes: []const u8) ConsoleError!usize {
        const self = context.console;
        for (bytes) |c| {
            // Parse terminal color codes.
            if (self.term_parser.parse(c)) |term_color| {
                switch (term_color) {
                    .foreground => |fg| self.cur_fgc = fg,
                    .background => |bg| self.cur_bgc = bg,
                    .fg_default => self.cur_fgc = self.fgc,
                    .bg_default => self.cur_bgc = self.bgc,
                    .parsing => {},
                }
                continue;
            }

            if (c == '\n') {
                self.newline();
            } else {
                self.window.writeAscii(
                    @bitCast(8 * self.cur_col),
                    @bitCast(16 * self.cur_row),
                    c,
                    self.cur_fgc,
                    self.cur_bgc,
                );
                self.cur_col += 1;
                // The line exceeds the console width. Go to the next row.
                if (self.cur_col >= kCols) {
                    self.newline();
                }
            }
        }

        // Flush the console to render.
        gfx.layer.getLayers().flushLayer(self.window);

        return bytes.len;
    }

    /// Print an ascii message to the console.
    pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) void {
        format(
            ConsoleWriter{ .context = .{ .console = self } },
            fmt,
            args,
        ) catch unreachable;
    }

    fn newline(self: *Self) void {
        self.cur_col = 0;
        if (self.cur_row < kRows - 1) {
            self.cur_row += 1;
            return;
        }

        // Scroll up.
        self.window.shadow_writer.copyRectangle(
            .{ .x = 0, .y = 0 },
            .{ .x = 0, .y = 16 },
            .{ .x = 8 * kCols, .y = 16 * (kRows - 1) },
        );
        self.window.fillRectangle(
            .{ .x = 0, .y = 16 * (kRows - 1) },
            .{ .x = 8 * kCols, .y = 16 },
            self.bgc,
        );
    }

    /// Clear the console.
    fn clear(self: *Self) void {
        for (0..16 * kRows) |y| {
            for (0..8 * kCols) |x| {
                self.window.writeAt(
                    .{
                        .x = @intCast(x),
                        .y = @intCast(y),
                    },
                    self.cur_bgc,
                );
            }
        }
    }
};

const TermColorTag = enum {
    foreground,
    background,
    fg_default,
    bg_default,
    parsing,
};

const TermColor = union(TermColorTag) {
    foreground: PixelColor,
    background: PixelColor,
    fg_default: void,
    bg_default: void,
    parsing: void,
};

/// Tiny state machine to parse the terminal color codes.
/// TODO: make this more generic library.
const TermParser = struct {
    const Self = @This();

    /// Color code sequence started.
    /// True since the last character is '\x1B'.
    /// Set back to false when the character is '['.
    started: bool = false,
    /// Received the '[' character.
    bracketed: bool = false,
    /// Ignoring unsupported codes.
    ignoring: bool = false,
    /// Color code.
    code: usize = 0,

    pub fn new() Self {
        return Self{};
    }

    /// Parse a character.
    /// If the character is a special one, this function returns non-null value.
    pub fn parse(self: *Self, c: u8) ?TermColor {
        if (self.started) {
            if (self.bracketed) {
                switch (c) {
                    'm' => {
                        self.started = false;
                        self.bracketed = false;
                        const ret = if (self.ignoring) TermColor.parsing else Self.code2color(self.code);
                        self.code = 0;
                        self.ignoring = false;
                        return ret;
                    },
                    ';' => {
                        self.ignoring = true;
                        return TermColor.parsing;
                    },
                    else => {
                        if (self.ignoring) return TermColor.parsing;
                        self.code = self.code * 10 + (c - '0');
                        return TermColor.parsing;
                    },
                }
            } else {
                self.bracketed = c == '[';
                return TermColor.parsing;
            }
        } else {
            if (c == 0x1B) {
                self.started = true;
                return TermColor.parsing;
            }
        }

        return null;
    }

    fn code2color(code: usize) ?TermColor {
        return switch (code) {
            30 => TermColor{ .foreground = colors.Black },
            31 => TermColor{ .foreground = colors.Red },
            32 => TermColor{ .foreground = colors.Green },
            33 => TermColor{ .foreground = colors.Yellow },
            34 => TermColor{ .foreground = colors.Blue },
            37 => TermColor{ .foreground = colors.White },
            39 => TermColor.fg_default,

            40 => TermColor{ .background = colors.Black },
            41 => TermColor{ .background = colors.Red },
            42 => TermColor{ .background = colors.Green },
            43 => TermColor{ .background = colors.Yellow },
            44 => TermColor{ .background = colors.Blue },
            47 => TermColor{ .background = colors.White },
            49 => TermColor.bg_default,

            100 => TermColor{ .background = colors.LightGray },

            else => TermColor.parsing,
        };
    }
};
