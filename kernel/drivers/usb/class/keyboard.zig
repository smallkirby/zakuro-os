//! This file provides a USB HID mouse class driver.

const std = @import("std");
const log = std.log.scoped(.kbd);
const Allocator = std.mem.Allocator;

const ClassDriver = @import("driver.zig").ClassDriver;
const Error = @import("driver.zig").ClassDriverError;

const zakuro = @import("zakuro");
const UsbDevice = zakuro.drivers.usb.device.UsbDevice;
const InterfaceDescriptor = @import("../descriptor.zig").InterfaceDescriptor;

/// Instance of observer for key events.
pub var keyboard_observer: ?*const KeyboardObserver = null;

/// USB HID keyboard class driver.
pub const KeyboardDriver = struct {
    const Self = @This();

    /// Instantiate the mouse driver.
    pub fn new(dev: *UsbDevice, if_index: u8, allocator: Allocator) Error!ClassDriver {
        const keyboard = allocator.create(Self) catch return Error.AllocationFailed;
        keyboard.* = Self{};

        return ClassDriver{
            .ptr = keyboard,
            .device = dev,
            .if_index = if_index,
            .in_packed_size = 8,
            .vtable = &.{
                .onDataReceived = Self.onDataReceived,
            },
        };
    }

    fn onDataReceived(_: *anyopaque, buf: []u8) void {
        if (keyboard_observer) |observer| {
            observer.onEvent(RawKeyEvent.new(buf[0..@sizeOf(RawKeyEvent)]));
        }
    }
};

/// Return true if the descriptor is for a keyboard device.
pub fn isMe(desc: InterfaceDescriptor) bool {
    return desc.interface_protocol == 0x01;
}

/// Observer for the keyboard driver.
/// The observer can be notified on keyboard events.
pub const KeyboardObserver = struct {
    /// Instance of the observer.
    ptr: *anyopaque,
    /// vtable for the observer.
    vtable: VTable,

    const Self = @This();
    const VTable = struct {
        onEvent: *const fn (*anyopaque, RawKeyEvent) void,
    };

    pub fn onEvent(self: *const Self, event: RawKeyEvent) void {
        self.vtable.onEvent(self.ptr, event);
    }
};

/// Raw key event sent by keyboard USB driver.
pub const RawKeyEvent = packed struct(u64) {
    modifier: ModifierKey,
    _reserved: u8,
    key1: u8,
    key2: u8,
    key3: u8,
    key4: u8,
    key5: u8,
    key6: u8,

    pub fn new(data: *[8]u8) RawKeyEvent {
        return .{
            .modifier = @bitCast(data[0]),
            ._reserved = data[1],
            .key1 = data[2],
            .key2 = data[3],
            .key3 = data[4],
            .key4 = data[5],
            .key5 = data[6],
            .key6 = data[7],
        };
    }
};

pub const ModifierKey = packed struct(u8) {
    control: bool,
    shift: bool,
    alt: bool,
    gui: bool,
    rcontrol: bool,
    rshift: bool,
    ralt: bool,
    rgui: bool,
};
