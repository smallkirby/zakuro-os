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
