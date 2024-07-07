const std = @import("std");
const log = std.log.scoped(.kbd);
const Allocator = std.mem.Allocator;

const zakuro = @import("zakuro");
const drivers = zakuro.drivers;
const cls_keyboard = drivers.usb.cls_keyboard;
const KeyboardDriver = drivers.usb.KeyboardObserver;
const KeyboardObserver = drivers.usb.KeyboardObserver;
const event = zakuro.event;
const ModifierKey = cls_keyboard.ModifierKey;
const RawKeyEvent = cls_keyboard.RawKeyEvent;

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
                .onEvent = Self.pushEvent,
            },
        };

        return ret;
    }

    fn pushEvent(_: *anyopaque, key_event: RawKeyEvent) void {
        if (findValidKey(key_event)) |key| {
            event.push(.{ .kbd = .{
                .code = key,
                .ascii = code2ascii(key, key_event.modifier),
            } }) catch unreachable;
        }
    }

    inline fn findValidKey(key_event: RawKeyEvent) ?u8 {
        if (key_event.key1 != 0) {
            return key_event.key1;
        } else if (key_event.key2 != 0) {
            return key_event.key2;
        } else if (key_event.key3 != 0) {
            return key_event.key3;
        } else if (key_event.key4 != 0) {
            return key_event.key4;
        } else if (key_event.key5 != 0) {
            return key_event.key5;
        } else if (key_event.key6 != 0) {
            return key_event.key6;
        } else {
            return null;
        }
    }

    inline fn code2ascii(code: u8, modifier: ModifierKey) u8 {
        if (modifier.shift) {
            return shifted_keycode_map[code];
        } else {
            return keycode_map[code];
        }
    }
};

const keycode_map: [256]u8 = [_]u8{
    0,    0,    0,    0,    'a',  'b', 'c', 'd',
    'e',  'f',  'g',  'h',  'i',  'j', 'k', 'l',
    'm',  'n',  'o',  'p',  'q',  'r', 's', 't',
    'u',  'v',  'w',  'x',  'y',  'z', '1', '2',
    '3',  '4',  '5',  '6',  '7',  '8', '9', '0',
    '\n', 0,    0x08, '\t', ' ',  '-', '=', '[',
    ']',  '\\', 0,    ';',  '\'', '`', ',', '.',
    '/',  0,    0,    0,    0,    0,   0,   0,
    0,    0,    0,    0,    0,    0,   0,   0,
    0,    0,    0,    0,    0,    0,   0,   0,
    0,    0,    0,    0,    '/',  '*', '-', '+',
    '\n', '1',  '2',  '3',  '4',  '5', '6', '7',
    '8',  '9',  '0',  '.',  '\\', 0,   0,   '=',
} ++ [_]u8{0} ** (152);

const shifted_keycode_map: [256]u8 = [_]u8{
    0,    0,   0,    0,    'A',  'B', 'C', 'D',
    'E',  'F', 'G',  'H',  'I',  'J', 'K', 'L',
    'M',  'N', 'O',  'P',  'Q',  'R', 'S', 'T',
    'U',  'V', 'W',  'X',  'Y',  'Z', '!', '@',
    '#',  '$', '%',  '^',  '&',  '*', '(', ')',
    '\n', 0,   0x08, '\t', ' ',  '_', '+', '{',
    '}',  '|', 0,    ':',  '"',  '~', '<', '>',
    '?',  0,   0,    0,    0,    0,   0,   0,
    0,    0,   0,    0,    0,    0,   0,   0,
    0,    0,   0,    0,    0,    0,   0,   0,
    0,    0,   0,    0,    '/',  '*', '-', '+',
    '\n', '1', '2',  '3',  '4',  '5', '6', '7',
    '8',  '9', '0',  '.',  '\\', 0,   0,   '=',
} ++ [_]u8{0} ** (152);

/// Key event processed by the keyboard driver.
pub const KeyEvent = struct {
    code: u8,
    ascii: u8,
};
