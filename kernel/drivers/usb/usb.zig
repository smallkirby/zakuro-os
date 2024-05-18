pub const setupdata = @import("setupdata.zig");
pub const endpoint = @import("endpoint.zig");
pub const descriptor = @import("descriptor.zig");
pub const device = @import("device.zig");
pub const controller = @import("controller.zig");
pub const xhc = @import("xhci/xhc.zig");

pub const cls_mouse = @import("class/mouse.zig");
pub const MouseObserver = cls_mouse.MouseObserver;

test {
    @import("std").testing.refAllDecls(@This());
}
