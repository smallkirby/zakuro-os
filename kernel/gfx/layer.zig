const std = @import("std");
const log = std.log.scoped(.layer);
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Window = @import("window.zig").Window;

const zakuro = @import("zakuro");
const gfx = zakuro.gfx;
const PixelWriter = gfx.PixelWriter;
const Pos = zakuro.Vector(i32);

const LayerError = error{
    /// Failed to allocate memory.
    NoMemory,
};
const Error = LayerError;

pub const LayeredWriter = struct {
    const Self = @This();
    const LayerList = ArrayList(Layer);

    /// Pixel writer.
    writer: PixelWriter,
    /// List of layers.
    layers_stack: LayerList,
    /// ID of the next layer.
    next_id: usize = 0,

    allocator: Allocator,

    pub fn init(writer: PixelWriter, allocator: Allocator) Self {
        return Self{
            .writer = writer,
            .layers_stack = LayerList.init(allocator),
            .allocator = allocator,
        };
    }

    /// Generate a new layer.
    pub fn spawnLayer(self: *Self) Error!*Layer {
        self.layers_stack.append(Layer.init(self.next_id)) catch return Error.NoMemory;
        self.next_id += 1;

        return &self.layers_stack.items[self.layers_stack.items.len - 1];
    }

    inline fn findLayer(self: *Self, id: usize) ?*Layer {
        const ix = self.findLayerIndex(id) orelse return null;
        return &self.layers_stack.items[ix];
    }

    fn findLayerIndex(self: *Self, id: usize) ?usize {
        for (self.layers_stack.items, 0..) |*layer, ix| {
            if (layer.id == id) {
                return ix;
            }
        }
        return null;
    }

    /// Move the specified layer to the given position.
    pub fn move(self: *Self, id: usize, pos: Pos) void {
        if (self.findLayer(id)) |layer| {
            layer.origin = pos;
        } else {
            unreachable;
        }
    }

    /// Move the specified layer by the given delta.
    pub fn moveRelative(self: *Self, id: usize, delta: Pos) void {
        if (self.findLayer(id)) |layer| {
            layer.origin.x += delta.x;
            layer.origin.y += delta.y;
        } else {
            unreachable;
        }
    }

    /// Draw all layers from the bottom to the top.
    pub fn draw(self: *Self) void {
        for (self.layers_stack.items) |layer| {
            if (layer.visible) {
                layer.draw(self.writer);
            }
        }
    }

    /// Make the specified layer invisible.
    pub fn hide(self: *Self, id: usize) void {
        if (self.findLayer(id)) |layer| {
            layer.visible = false;
        } else {
            unreachable;
        }
    }

    /// Set the z-index of the specified layer.
    /// If the z-index exceeds the number of layers, the layer is moved to the top.
    /// If the z-index is negative, the layer is made invisible.
    pub fn setZ(self: *Self, id: usize, z: usize) void {
        var pos = z;
        if (z >= self.layers_stack.items.len) {
            pos = self.layers_stack.items.len - 1;
        }
        if (pos < 0) {
            self.hide(id);
            return;
        }

        const old_pos = self.findLayerIndex(id) orelse unreachable;
        const new_pos = if (pos == self.layers_stack.items.len - 1) pos - 1 else pos;
        const layer = self.layers_stack.orderedRemove(old_pos);
        self.layers_stack.insert(new_pos, layer);
    }

    pub fn deinit(self: *Self) void {
        for (self.layers_stack.items) |layer| {
            layer.deinit();
            self.allocator.free(layer);
        }
        self.layers_stack.deinit();
    }
};

/// Layer is a collection of windows.
/// Layer itself has a infinite size.
/// When a layer is below another layer, it is not visible.
pub const Layer = struct {
    const Self = @This();

    /// Unique ID of the layer.
    id: usize,
    /// Origin of the layer.
    origin: Pos,
    /// Window on the layer.
    window: ?*Window,
    /// Whether the layer is visible.
    visible: bool = true,

    /// Initialize the layer.
    /// Caller MUST call deinit() when the layer is no longer needed.
    pub fn init(id: usize) Self {
        return Self{
            .id = id,
            .origin = .{ .x = 0, .y = 0 },
            .window = null,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self; // autofix
        // TODO: should we deinit the window here?
    }

    /// Renders the window on the layer.
    pub fn draw(self: *Self, writer: PixelWriter) void {
        self.window.drawAt(self.origin, writer);
    }
};

test {
    std.testing.refAllDecls(@This());
}
