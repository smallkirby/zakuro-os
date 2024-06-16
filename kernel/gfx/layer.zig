const std = @import("std");
const log = std.log.scoped(.layer);
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Window = @import("window.zig").Window;

const zakuro = @import("zakuro");
const gfx = zakuro.gfx;
const PixelWriter = gfx.PixelWriter;
const Pos = zakuro.Vector(u32);

const LayerError = error{
    /// Failed to allocate memory.
    NoMemory,
};
const Error = LayerError;

/// Global instance of the window layers.
var layers: Layers = undefined;

pub fn getLayers() *Layers {
    return &layers;
}

/// Initialize the global layered writer.
pub fn initialize(pixel_writer: PixelWriter, fb_config: gfx.FrameBufferConfig, allocator: Allocator) void {
    layers = Layers.init(pixel_writer, fb_config, allocator);
}

/// Manages a list of windows and their drawing order.
const Layers = struct {
    const Self = @This();
    const WindowList = ArrayList(Window);

    /// Pixel writer.
    writer: PixelWriter,
    /// List of windows.
    windows_stack: WindowList,

    allocator: Allocator,
    fb_config: gfx.FrameBufferConfig,

    pub fn init(writer: PixelWriter, fb_config: gfx.FrameBufferConfig, allocator: Allocator) Self {
        return Self{
            .writer = writer,
            .windows_stack = WindowList.init(allocator),
            .allocator = allocator,
            .fb_config = fb_config,
        };
    }

    /// Generate a new window.
    pub fn spawnWindow(self: *Self, width: u32, height: u32) Error!*Window {
        self.windows_stack.append(try Window.init(
            width,
            height,
            self.fb_config,
            self.allocator,
        )) catch return Error.NoMemory;

        return &self.windows_stack.items[self.windows_stack.items.len - 1];
    }

    /// Draw all windows from the bottom to the top.
    pub fn flush(self: *Self) void {
        for (self.windows_stack.items) |*window| {
            if (window.visible) {
                window.flush(self.writer);
            }
        }
    }

    pub fn deinit(self: *Self) void {
        for (self.windows_stack.items) |*window| {
            window.deinit();
            self.allocator.free(window);
        }
        self.windows_stack.deinit();
    }
};
