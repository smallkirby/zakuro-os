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
    /// Next window ID.
    next_id: usize = 0,
    /// Writer for a back-buffer.
    back_writer: PixelWriter,
    /// Length of the back buffer.
    back_buffer_size: usize,

    allocator: Allocator,
    fb_config: gfx.FrameBufferConfig,

    pub fn init(writer: PixelWriter, fb_config: gfx.FrameBufferConfig, allocator: Allocator) Self {
        const back_buffer = allocator.alloc(u8, fb_config.horizontal_resolution * fb_config.vertical_resolution * gfx.bytes_per_pixel) catch {
            @panic("Failed to allocate a back buffer for Layers.");
        };
        const back_config = allocator.create(gfx.FrameBufferConfig) catch {
            @panic("Failed to allocate a back buffer for Layers.");
        };
        back_config.frame_buffer = @ptrCast(back_buffer);
        back_config.horizontal_resolution = fb_config.horizontal_resolution;
        back_config.vertical_resolution = fb_config.vertical_resolution;
        back_config.pixels_per_scan_line = fb_config.pixels_per_scan_line;
        back_config.pixel_format = fb_config.pixel_format;

        return Self{
            .writer = writer,
            .windows_stack = WindowList.init(allocator),
            .allocator = allocator,
            .fb_config = fb_config,
            .back_writer = PixelWriter.new(back_config),
            .back_buffer_size = fb_config.horizontal_resolution * fb_config.vertical_resolution * gfx.bytes_per_pixel,
        };
    }

    /// Generate a new window.
    pub fn spawnWindow(self: *Self, width: u32, height: u32, draggable: bool) Error!*Window {
        self.windows_stack.append(try Window.init(
            self.next_id,
            width,
            height,
            draggable,
            self.back_writer.config.*,
            self.allocator,
        )) catch return Error.NoMemory;
        self.next_id += 1;

        return &self.windows_stack.items[self.windows_stack.items.len - 1];
    }

    /// Renders all windows from the bottom to the top.
    pub fn flush(self: *Self) void {
        self.flushLayer(&self.windows_stack.items[0]);
    }

    /// Renders the specified window layer and all the layers above it.
    pub fn flushLayer(self: *Self, window: *Window) void {
        var draw = false;
        for (self.windows_stack.items) |*cur_win| {
            if (cur_win.id == window.id) {
                if (!cur_win.visible) return;
                draw = true;
            }
            if (draw and cur_win.visible) {
                cur_win.flush(self.back_writer);
            }
        }

        if (draw) {
            @memcpy(
                self.writer.config.frame_buffer[0..self.back_buffer_size],
                self.back_writer.config.frame_buffer[0..self.back_buffer_size],
            );
        }
    }

    /// Get a visible window that contains the specified position.
    pub fn findLayerByPosition(self: *Self, pos: Pos, excluded_id: usize) ?*Window {
        var id = self.windows_stack.items.len - 1;
        while (id >= 0) : (id -= 1) {
            const window = &self.windows_stack.items[id];
            if (window.visible and window.id != excluded_id) {
                if (!window.draggable) return null;
                if (window.origin.x <= pos.x and pos.x < window.origin.x + window.width and
                    window.origin.y <= pos.y and pos.y < window.origin.y + window.height)
                {
                    return window;
                }
            }
        }
        return null;
    }

    pub fn deinit(self: *Self) void {
        for (self.windows_stack.items) |*window| {
            window.deinit();
            self.allocator.free(window);
        }
        self.windows_stack.deinit();
    }
};
