//! This file provides a USB specicifi device.
//! Note that this device is more abstract than xHCI device.

const std = @import("std");
const endpoint = @import("endpoint.zig");
const descriptor = @import("descriptor.zig");
const setupdata = @import("setupdata.zig");
const XhciDevice = @import("xhci/device.zig").XhciDevice;
const trbs = @import("xhci/trb.zig");
const regs = @import("xhci/register.zig");
const zakuro = @import("zakuro");
const Register = zakuro.mmio.Register;
const log = std.log.scoped(.usbdev);

pub const UsbDeviceError = error{
    /// Specified endpoint ID is invalid.
    InvalidEndpointId,
    /// Transfer Ring is not set or available.
    TransferRingUnavailable,
};

/// USB device.
pub const UsbDevice = struct {
    /// General purpose buffer for this device.
    /// Any alignment is allowed.
    buffer: [256]u8 = [_]u8{0} ** 256,
    /// xHCI Device
    dev: XhciDevice,
    /// Doorbell Register.
    db: *volatile Register(regs.DoorbellRegister, .DWORD),

    pub const Self = @This();

    /// Start initialization of the device and get the descriptor.
    pub fn startup(
        self: *Self,
        epid: endpoint.EndpointId,
        desc_type: descriptor.DescriptorType,
        desc_index: u8,
        buf: []u8,
    ) !void {
        const sud = setupdata.SetupData{
            .bm_request_type = .{
                .dtd = .In,
                .type = .Standard,
                .recipient = .Device,
            },
            .b_request = .GetDescriptor,
            .w_value = (@intFromEnum(desc_type) << 8) + desc_index,
            .windex = 0,
            .w_length = @intCast(buf.len),
        };

        try self.getDescriptor(epid, sud, buf);
    }

    /// Get the descriptor of the device.
    pub fn getDescriptor(
        self: *Self,
        ep_id: endpoint.EndpointId,
        sud: setupdata.SetupData,
        buf: []u8,
    ) !void {
        if (15 < ep_id.number) {
            return UsbDeviceError.InvalidEndpointId;
        }
        const dci = ep_id.addr();
        const tr = self.dev.transfer_rings[dci - 1] orelse return UsbDeviceError.TransferRingUnavailable;

        var setup_trb = trbs.SetupStageTrb{
            .bm_request_type = @bitCast(sud.bm_request_type),
            .b_request = @intFromEnum(sud.b_request),
            .w_value = sud.w_value,
            .w_index = sud.windex,
            .w_length = sud.w_length,
            .trt = .InDataStage,
            .interrupter_target = 0, // TODO
        };
        _ = tr.push(@ptrCast(&setup_trb));
        var data_trb = trbs.DataStageTrb{
            .trb_buffer_pointer = @intFromPtr(buf.ptr),
            .trb_transfer_length = @truncate(buf.len),
            .td_size = 0,
            .dir = .In,
            .ioc = true,
            .interrupter_target = 0, // TODO
        };
        _ = tr.push(@ptrCast(&data_trb));
        var status_trb = trbs.StatusStageTrb{
            .interrupter_target = 0,
            .ent = false,
            .ch = false,
            .ioc = false,
            .dir = .In,
        };
        _ = tr.push(@ptrCast(&status_trb));

        self.db.write(.{
            .db_stream_id = 0,
            .db_target = @intCast(dci),
        });
    }

    fn controlIn(ep_id: endpoint.EndpointId, sud: setupdata.SetupData, buf: []u8) void {
        // unimplemented
        _ = ep_id; // autofix
        _ = sud; // autofix
        _ = buf; // autofix
    }
};
