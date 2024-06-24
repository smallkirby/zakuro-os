const std = @import("std");
const log = std.log.scoped(.kbd);
const Allocator = std.mem.Allocator;

const zakuro = @import("zakuro");
const drivers = zakuro.drivers;
const cls_keyboard = drivers.usb.cls_keyboard;
const KeyboardDriver = drivers.usb.KeyboardObserver;
const KeyboardObserver = drivers.usb.KeyboardObserver;
const KeyEvent = cls_keyboard.KeyEvent;

pub const Keyboard = struct {
    const Self = @This();

    pub fn new() Self {
        return .{};
    }

    pub fn observer(self: *Self, allocator: Allocator) !*KeyboardObserver {
        const ret = try allocator.create(KeyboardObserver);
        ret.* = .{
            .ptr = self,
            .vtable = .{
                .onEvent = Self.onKeyEvent,
            },
        };

        return ret;
    }

    fn onKeyEvent(cxt: *anyopaque, event: KeyEvent) void {
        const self: *Self = @ptrCast(cxt);
        _ = self;

        log.info("Key event: {?}\n", .{event});
    }
};
