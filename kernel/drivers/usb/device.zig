//! This file provides a USB specicifi device.
//! Note that this device is more abstract than xHCI device.

const std = @import("std");
const endpoint = @import("endpoint.zig");
const descriptor = @import("descriptor.zig");
const setupdata = @import("setupdata.zig");
const descs = @import("descriptor.zig");
const class = @import("class.zig");
const XhciDevice = @import("xhci/device.zig").XhciDevice;
const trbs = @import("xhci/trb.zig");
const regs = @import("xhci/register.zig");
const ring = @import("xhci/ring.zig");
const zakuro = @import("zakuro");
const Register = zakuro.mmio.Register;
const log = std.log.scoped(.usbdev);

pub const UsbDeviceError = error{
    /// Specified endpoint ID is invalid.
    InvalidEndpointId,
    /// Transfer Ring is not set or available.
    TransferRingUnavailable,
    /// Memory allocation failed.
    AllocationFailed,
    /// No corresponding SetupStageTrb in the record.
    NoCorrespondingSetupTrb,
    /// Descriptor returned by the divice is invalid.
    InvalidDescriptor,
    /// Invalid initialization phase.
    InvalidPhase,
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
    /// Phase of the initialization.
    phase: InitializationPhase = .NotAddressed,
    /// Index of the configuration descriptor currently being processed.
    config_index: u8,
    /// Number of configuration descriptors this device has.
    num_config: u8,

    /// Map that associate SetupStageTrb with DataStageTrb.
    setup_trb_map: SetupTrbMap,
    /// Allocator used by this device internally to manage TRBs.
    allocator: std.mem.Allocator,

    pub const Self = @This();
    const SetupTrbMap = std.hash_map.AutoHashMap(*trbs.Trb, *trbs.Trb);
    const RegDoorbell = Register(regs.DoorbellRegister, .DWORD);

    /// Initialize the device structure.
    pub fn initialize(
        self: *Self,
        tr: []?*ring.Ring,
        slot_id: usize,
        db: *volatile RegDoorbell,
        allocator: std.mem.Allocator,
    ) void {
        self.dev.transfer_rings = tr;
        self.dev.slot_id = slot_id;
        self.db = db;
        self.setup_trb_map = SetupTrbMap.init(allocator);
        self.allocator = allocator;
        self.phase = .NotAddressed;
        self.config_index = 0;
        self.num_config = 0;
    }

    /// Get the specified type of descriptor.
    fn getDescriptor(
        self: *Self,
        ep_id: endpoint.EndpointId,
        desc_type: descs.DescriptorType,
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
            .w_value = (@as(u16, @intFromEnum(desc_type)) << 8) + desc_index,
            .w_index = 0,
            .w_length = @intCast(buf.len),
        };

        try self.controlIn(ep_id, sud, buf);
    }

    /// Start the initialization of the USB device.
    pub fn start_device_init(self: *Self) !void {
        if (self.phase != .NotAddressed) {
            return UsbDeviceError.InvalidPhase;
        }
        self.phase = .Phase1;

        try self.getDescriptor(
            endpoint.default_control_pipe_id,
            .Device,
            0,
            &self.buffer,
        );
    }

    /// Get the configuration descriptor and associated interface descriptors.
    fn init_one(self: *Self, device_desc: *descs.DeviceDescriptor) !void {
        if (self.phase != .Phase1) {
            return UsbDeviceError.InvalidPhase;
        }

        self.phase = .Phase2;
        self.num_config = device_desc.num_configurations;
        self.config_index = 0;

        try self.getDescriptor(
            endpoint.default_control_pipe_id,
            .Configuration,
            self.config_index,
            &self.buffer,
        );
    }

    /// TODO: doc
    fn init_second(self: *Self, buf: []u8) !void {
        const first_desc: *descs.ConfigurationDescriptor = @alignCast(@ptrCast(buf.ptr));
        if (first_desc.descriptor_type != .Configuration) {
            return UsbDeviceError.InvalidDescriptor;
        }
        if (self.phase != .Phase2) {
            return UsbDeviceError.InvalidPhase;
        }

        self.phase = .Phase3;

        var bytes_consumed: usize = 0;
        while (bytes_consumed <= buf.len) {
            var p = buf[bytes_consumed..].ptr;
            const if_desc: *align(1) descs.InterfaceDescriptor = @alignCast(@ptrCast(p));
            log.debug("p = {*}", .{p});
            bytes_consumed += if_desc.length;
            p += if_desc.length;

            if (if_desc.descriptor_type != .Interface) {
                continue;
            }

            const class_driver = class.newClassDriver(self, if_desc.*) catch continue; // TODO;
            _ = class_driver; // autofix
            for (0..if_desc.num_endpoints) |_| {
                if (p[1] != @intFromEnum(descs.DescriptorType.Endpoint)) continue;
                const ep_desc: *align(1) descs.EndpointDescriptor = @alignCast(@ptrCast(p));
                bytes_consumed += ep_desc.length;
                p += ep_desc.length;
                log.debug("{?}", .{ep_desc});

                // TODO: unimplemented: handle the endpoint descriptor
            }
        }

        // TODO: unimplemented: increment the phase
    }

    /// Handle the transfer event.
    pub fn onTransferEventReceived(
        self: *Self,
        trb: *volatile trbs.TransferEventTrb,
    ) !void {
        const issuer_trb: *trbs.Trb = @ptrFromInt(trb.trb_pointer);
        if (issuer_trb.trb_type == .Normal) {
            @panic("Unimplemented: Transfer Event generated by Normal TRB.");
        }

        // Fulfill the SetupData with the SetupStageTRB.
        const setup_trb = try self.popCorrespondingSetupTrb(issuer_trb);
        const sud = setupdata.SetupData{
            .b_request = @enumFromInt(setup_trb.b_request),
            .bm_request_type = @bitCast(setup_trb.bm_request_type),
            .w_value = setup_trb.w_value,
            .w_index = setup_trb.w_index,
            .w_length = setup_trb.w_length,
        };

        // Get the data buffer and its length.
        var data_stage_buf: ?[*]u8 = null;
        // Transfer Event TRB's transfer_length field is the total length of the data buffer
        // minus the length of the data transferred by the TRB.
        // The residual length is the length of the data transferred by the issuer TRB.
        var transfer_length: usize = 0;
        switch (issuer_trb.trb_type) {
            .DataStage => {
                const data_trb: *trbs.DataStageTrb = @ptrCast(issuer_trb);
                data_stage_buf = @ptrFromInt(data_trb.trb_buffer_pointer);
                transfer_length = data_trb.trb_transfer_length - trb.trb_transfer_length;
            },
            .StatusStage => {},
            else => {
                log.err("Unimplemented: Transfer Event generated by TRB of type {?}.", .{issuer_trb.trb_type});
                @panic("");
            },
        }

        const ep_id = endpoint.EndpointId.from(trb.eid);
        const buf: ?[]u8 = if (data_stage_buf) |b| b[0..transfer_length] else null;

        try self.onControlComplete(ep_id, sud, buf);
    }

    /// Handle the control transfer completion.
    fn onControlComplete(
        self: *Self,
        ep_id: endpoint.EndpointId,
        sud: setupdata.SetupData,
        buf: ?[]u8,
    ) !void {
        _ = sud; // autofix
        _ = ep_id; // autofix

        switch (self.phase) {
            .NotAddressed => @panic("onControlComplete is called while the initialization has not started."),
            .Phase1 => {
                if (buf) |b| {
                    const desc: *descs.DeviceDescriptor = @alignCast(@ptrCast(b.ptr));
                    if (desc.descriptor_type != .Device) return UsbDeviceError.InvalidDescriptor;
                    try self.init_one(desc);
                } else {
                    return UsbDeviceError.InvalidPhase;
                }
            },
            .Phase2 => {
                if (buf) |b| {
                    try self.init_second(b);
                } else {
                    return UsbDeviceError.InvalidPhase;
                }
            },
            else => @panic("Unimplemented: onControlComplete"),
        }
    }

    /// Get the SetupStageTrb corresponding to the issuer TRB,
    /// then remove the pair from the map.
    pub fn popCorrespondingSetupTrb(
        self: *Self,
        issuer_trb: *trbs.Trb,
    ) UsbDeviceError!*trbs.SetupStageTrb {
        const trb = self.setup_trb_map.get(issuer_trb) orelse return UsbDeviceError.NoCorrespondingSetupTrb;
        _ = self.setup_trb_map.remove(issuer_trb);
        return @ptrCast(trb);
    }

    /// Delete the TRB pair from the map.
    pub fn deleteFromMap(self: *Self, issuer_trb: *trbs.Trb) void {
        _ = self.setup_trb_map.remove(issuer_trb);
    }

    fn controlIn(
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
            .w_index = sud.w_index,
            .w_length = sud.w_length,
            .trt = .InDataStage,
            .interrupter_target = 0, // TODO
        };
        const ptr_setup_trb = tr.push(@ptrCast(&setup_trb));
        var data_trb = trbs.DataStageTrb{
            .trb_buffer_pointer = @intFromPtr(buf.ptr),
            .trb_transfer_length = @truncate(buf.len),
            .td_size = 0,
            .dir = .In,
            .ioc = true,
            .interrupter_target = 0, // TODO
        };
        const ptr_data_trb = tr.push(@ptrCast(&data_trb));
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

        try self.setup_trb_map.put(@ptrCast(ptr_data_trb), @ptrCast(ptr_setup_trb));
    }
};

const InitializationPhase = enum(u8) {
    NotAddressed,
    Phase1,
    Phase2,
    Phase3,
    Complete,
};
