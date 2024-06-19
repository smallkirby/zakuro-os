const std = @import("std");

const zakuro = @import("zakuro");
const gfx = zakuro.gfx;
const color = zakuro.color;
const Window = gfx.window.Window;

pub fn drawDesktop(window: *Window) void {
    for (0..window.width) |x| {
        for (0..window.height) |y| {
            window.writeAt(
                .{ .x = @truncate(x), .y = @truncate(y) },
                color.LightPurple,
            );
        }
    }
}

pub fn drawDock(window: *Window) void {
    // Draw dock bar
    window.fillRectangle(
        .{ .x = @intCast(window.width - 0x30), .y = 0 },
        .{ .x = 0x30, .y = window.height },
        color.DarkPurple,
    );

    // Draw hot button (mock)
    for (0..3) |x| {
        for (0..3) |y| {
            window.fillRectangle(
                .{
                    .x = window.width - 0x20 + @as(u32, @truncate(x * 6)),
                    .y = window.height - 0x20 + @as(u32, @truncate(y * 6)),
                },
                .{ .x = 3, .y = 3 },
                color.White,
            );
        }
    }
}

pub const GfxWindow = struct {
    const Self = @This();

    /// Window to draw pixels.
    window: *Window,

    const close_btn_width = 22;
    const close_btn_height = 22;
    const close_btn = [close_btn_height]*const [close_btn_width:0]u8{
        ".........@@@@.........",
        ".......@@@@@@@@.......",
        ".....@@@@@@@@@@@@.....",
        "....@@@@@@@@@@@@@@....",
        "...@@@@@@@@@@@@@@@@...",
        "..@@@@@@@@@@@@@@@@@@..",
        "..@@@@@@@@@@@@@@@@@@..",
        ".@@@@@xx@@@@@@xx@@@@@.",
        "@@@@@@@xx@@@@xx@@@@@@@",
        "@@@@@@@@xx@@xx@@@@@@@@",
        "@@@@@@@@@xxxx@@@@@@@@@",
        "@@@@@@@@@xxxx@@@@@@@@@",
        "@@@@@@@@xx@@xx@@@@@@@@",
        "@@@@@@@xx@@@@xx@@@@@@@",
        ".@@@@@xx@@@@@@xx@@@@@.",
        "..@@@@@@@@@@@@@@@@@@..",
        "..@@@@@@@@@@@@@@@@@@..",
        "...@@@@@@@@@@@@@@@@...",
        "....@@@@@@@@@@@@@@....",
        ".....@@@@@@@@@@@@.....",
        ".......@@@@@@@@.......",
        ".........@@@@.........",
    };

    pub fn new(window: *Window) Self {
        return Self{ .window = window };
    }

    pub fn init(self: Self) void {
        self.window.drawRectangle(
            .{ .x = 0, .y = 0 },
            .{ .x = self.window.width, .y = self.window.height },
            .{ .r = 0x22, .g = 0x22, .b = 0x22 },
        );
        self.window.fillRectangle(
            .{ .x = 1, .y = 1 },
            .{ .x = self.window.width - 2, .y = 0x20 },
            .{ .r = 0x22, .g = 0x22, .b = 0x22 },
        );

        const close_btn_offset = zakuro.Vector(u32){ .x = 4, .y = 4 };
        for (0..close_btn_height) |_y| {
            const y: u32 = @truncate(_y);
            for (0..close_btn_width) |_x| {
                const x: u32 = @truncate(_x);
                if (close_btn[y][x] == '@') {
                    self.window.writeAt(
                        .{ .x = x + close_btn_offset.x, .y = y + close_btn_offset.y },
                        color.DarkGray,
                    );
                } else if (close_btn[y][x] == 'x') {
                    self.window.writeAt(
                        .{ .x = x + close_btn_offset.x, .y = y + close_btn_offset.y },
                        color.LightGray,
                    );
                }
            }
        }
    }
};
