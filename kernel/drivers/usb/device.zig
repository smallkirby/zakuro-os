//! This file provides a USB specicifi device.
//! Note that this device is more abstract than xHCI device.

const std = @import("std");
const endpoint = @import("endpoint.zig");
const descriptor = @import("descriptor.zig");
const setupdata = @import("setupdata.zig");
const descs = @import("descriptor.zig");
const class = @import("class.zig");
const ClassDriver = @import("class/driver.zig").ClassDriver;
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
    /// No event waiter
    NoWaiter,
};

/// USB device.
pub const UsbDevice = struct {
    pub const max_num_eps = 16;

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
    /// Class drivers for each endpoints.
    class_drivers: [max_num_eps]?ClassDriver = [_]?ClassDriver{null} ** max_num_eps,
    /// Information of each endpoints.
    endpoint_configs: [max_num_eps]?endpoint.EndpointInfo = [_]?endpoint.EndpointInfo{null} ** max_num_eps,

    /// Map that associate SetupStageTrb with DataStageTrb.
    setup_trb_map: SetupTrbMap,
    /// TODO: doc
    event_waiters: EventWaiterMap,
    /// Allocator used by this device internally to manage TRBs.
    allocator: std.mem.Allocator,

    pub const Self = @This();
    const SetupTrbMap = std.hash_map.AutoHashMap(*trbs.Trb, *trbs.Trb);
    const EventWaiterMap = std.hash_map.AutoHashMap(setupdata.SetupData, *ClassDriver);
    const RegDoorbell = Register(regs.DoorbellRegister, .DWORD);

    /// Initialize the device structure.
    pub fn initialize(
        self: *Self,
        tr: []?*ring.Ring,
        slot_id: usize,
        db: *volatile RegDoorbell,
        allocator: std.mem.Allocator,
    ) void {
        self.* = .{
            .dev = .{
                .transfer_rings = tr,
                .slot_id = slot_id,
                .input_context = undefined,
                .device_context = undefined,
            },
            .db = db,
            .setup_trb_map = SetupTrbMap.init(allocator),
            .event_waiters = EventWaiterMap.init(allocator),
            .allocator = allocator,
            .config_index = 0,
            .num_config = 0,
        };
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

    /// Issue Configure Endpoint Command and enable the endpoint.
    fn setConfiguration(
        self: *Self,
        ep_id: endpoint.EndpointId,
        config_value: u8,
    ) !void {
        const sud = setupdata.SetupData{
            .bm_request_type = .{
                .dtd = .Out,
                .type = .Standard,
                .recipient = .Device,
            },
            .b_request = .SetConfiguration,
            .w_index = 0,
            .w_length = 0,
            .w_value = @intCast(config_value),
        };

        try self.controlOut(ep_id, sud, null, null);
    }

    /// TODO: doc
    pub fn interruptIn(
        self: *Self,
        ep_id: endpoint.EndpointId,
        buf: []u8,
    ) !void {
        const ep_dci = ep_id.addr();
        const tr = self.dev.transfer_rings[ep_dci - 1] orelse return UsbDeviceError.TransferRingUnavailable;

        var normal_trb = trbs.NormalTrb{
            .data_buf_ptr = @intFromPtr(buf.ptr),
            .trb_transfer_length = @truncate(buf.len),
            .ioc = true,
            .isp = true,
            .interrupter_target = 0, // TODO
        };
        _ = tr.push(@ptrCast(&normal_trb));

        self.db.write(.{
            .db_stream_id = 0,
            .db_target = @intCast(ep_dci),
        });
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
        const config_desc: *descs.ConfigurationDescriptor = @alignCast(@ptrCast(buf.ptr));
        if (config_desc.descriptor_type != .Configuration) {
            return UsbDeviceError.InvalidDescriptor;
        }
        if (self.phase != .Phase2) {
            return UsbDeviceError.InvalidPhase;
        }

        // Read the interface descriptors and endpoint descriptors
        // to find devices of supported classes.
        var reader = DescReader.new(buf);
        var p: ?[*]u8 = buf.ptr;
        var if_found = false;

        while (p != null) : (p = reader.next()) {
            const if_desc: *align(1) descs.InterfaceDescriptor = @alignCast(@ptrCast(p));
            if (if_desc.descriptor_type != .Interface) {
                continue;
            }

            // Create a class driver from the found interface descriptor.
            const class_driver = class.newClassDriver(self, if_desc.*, self.allocator) catch continue; // TODO;
            var num_found_eps: usize = 0;
            if_found = true;
            log.debug("Slot {d:0>2}: Class driver instantiated.", .{self.dev.slot_id});

            // Find all endpoints associated with the interface.
            while (num_found_eps < if_desc.num_endpoints and p != null) : (p = reader.next()) {
                if (p.?[1] != @intFromEnum(descs.DescriptorType.Endpoint)) continue;
                const ep_desc: *align(1) descs.EndpointDescriptor = @alignCast(@ptrCast(p));
                const ep_info = endpoint.EndpointInfo.new(ep_desc.*);
                self.endpoint_configs[num_found_eps] = ep_info;
                self.class_drivers[ep_info.ep_id.addr()] = class_driver;
                num_found_eps += 1;
            }

            // We suppose that there is only one interface for each device.
            break;
        }

        if (!if_found) return;

        self.phase = .Phase3;
        log.debug("Requesting to set the configuration.", .{});

        try self.setConfiguration(
            endpoint.default_control_pipe_id,
            config_desc.configuration_value,
        );
    }

    /// Configure all endpoints included in the configuration.
    fn init_third(self: *Self, sud: setupdata.SetupData) !void {
        if (sud.b_request != .SetConfiguration) {
            return UsbDeviceError.InvalidDescriptor;
        }
        if (self.phase != .Phase3) {
            return UsbDeviceError.InvalidPhase;
        }

        for (0..self.num_config) |i| {
            const ep_info = self.endpoint_configs[i].?;
            const driver = &self.class_drivers[ep_info.ep_id.addr()].?;
            driver.setEndpoint(ep_info);
        }

        self.phase = .Complete;
    }

    /// TODO: doc
    pub fn onEndpointConfigured(self: *Self) !void {
        for (0..self.class_drivers.len) |i| {
            if (self.class_drivers[i] != null) {
                const d = &self.class_drivers[i].?;
                try d.onEndpointConfigured();
            }
        }
    }

    /// TODO: doc
    fn onInterruptComplete(self: *Self, ep_id: endpoint.EndpointId, buf: []u8) !void {
        if (self.class_drivers[ep_id.addr()]) |*driver| {
            try driver.onInterruptComplete(ep_id, buf);
        } else {
            return UsbDeviceError.NoWaiter;
        }
    }

    /// Handle the transfer event.
    pub fn onTransferEventReceived(
        self: *Self,
        trb: *volatile trbs.TransferEventTrb,
    ) !void {
        const issuer_trb: *trbs.Trb = @ptrFromInt(trb.trb_pointer);

        if (issuer_trb.trb_type == .Normal) {
            const normal_trb: *trbs.NormalTrb = @ptrCast(issuer_trb);
            const transfer_length = normal_trb.trb_transfer_length - trb.trb_transfer_length;
            const buf: [*]u8 = @ptrFromInt(normal_trb.data_buf_ptr);
            return try self.onInterruptComplete(
                endpoint.EndpointId.from(trb.eid),
                buf[0..transfer_length],
            );
        }

        log.debug(
            "Slot {d:0>2}: Transfer Event recieved: {s}, phase={s}",
            .{ self.dev.slot_id, @tagName(issuer_trb.trb_type), @tagName(self.phase) },
        );

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
        if (self.phase == .Complete) {
            const waiter = self.popCorrespondingWaiter(sud) catch return UsbDeviceError.NoWaiter;
            return try waiter.onControlComplete();
        }

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
            .Phase3 => {
                try self.init_third(sud);
                log.info(
                    "Slot {d:0>2}: Device initialization completed: EPID={d}.",
                    .{ self.dev.slot_id, ep_id.addr() },
                );
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

    fn popCorrespondingWaiter(
        self: *Self,
        sud: setupdata.SetupData,
    ) !*ClassDriver {
        const waiter = self.event_waiters.get(sud) orelse return UsbDeviceError.NoCorrespondingSetupTrb;
        _ = self.event_waiters.remove(sud);
        return waiter;
    }

    /// Delete the TRB pair from the map.
    pub fn deleteFromMap(self: *Self, issuer_trb: *trbs.Trb) void {
        _ = self.setup_trb_map.remove(issuer_trb);
    }

    /// TODO: doc
    pub fn controlOut(
        self: *Self,
        ep_id: endpoint.EndpointId,
        sud: setupdata.SetupData,
        buf: ?[]u8,
        issuer: ?*ClassDriver,
    ) !void {
        if (issuer) |drv| {
            try self.event_waiters.put(sud, drv);
        }

        if (15 < ep_id.number) {
            return UsbDeviceError.InvalidEndpointId;
        }

        const dci = ep_id.addr();
        const tr = self.dev.transfer_rings[dci - 1] orelse return UsbDeviceError.TransferRingUnavailable;

        var status_trb = trbs.StatusStageTrb{
            .ioc = false,
            .dir = .Out,
        };
        if (buf) |b| {
            var setup_trb = trbs.SetupStageTrb{
                .bm_request_type = @bitCast(sud.bm_request_type),
                .b_request = @intFromEnum(sud.b_request),
                .w_value = sud.w_value,
                .w_index = sud.w_index,
                .w_length = sud.w_length,
                .trt = .OutDataStage,
                .interrupter_target = 0, // TODO
            };
            var data_trb = trbs.DataStageTrb{
                .trb_buffer_pointer = @intFromPtr(b.ptr),
                .trb_transfer_length = @truncate(b.len),
                .td_size = 0,
                .dir = .Out,
                .ioc = true,
                .interrupter_target = 0, // TODO
            };

            const ptr_setup_trb = tr.push(@ptrCast(&setup_trb));
            const ptr_data_trb = tr.push(@ptrCast(&data_trb));
            _ = tr.push(@ptrCast(&status_trb));

            try self.setup_trb_map.put(@ptrCast(ptr_data_trb), @ptrCast(ptr_setup_trb));
        } else {
            var setup_trb = trbs.SetupStageTrb{
                .bm_request_type = @bitCast(sud.bm_request_type),
                .b_request = @intFromEnum(sud.b_request),
                .w_value = sud.w_value,
                .w_index = sud.w_index,
                .w_length = sud.w_length,
                .trt = .NoDataStage,
                .interrupter_target = 0,
            };
            status_trb.ioc = true;

            const ptr_setup_trb = tr.push(@ptrCast(&setup_trb));
            const ptr_status_trb = tr.push(@ptrCast(&status_trb));

            try self.setup_trb_map.put(@ptrCast(ptr_status_trb), @ptrCast(ptr_setup_trb));
        }

        self.db.write(.{
            .db_stream_id = 0,
            .db_target = @intCast(dci),
        });

        log.debug(
            "Slot {d:0>2}: Issued a control out transfer: EPID={d}",
            .{ self.dev.slot_id, ep_id.addr() },
        );
    }

    /// TODO: doc
    pub fn controlIn(
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

/// Reader for USB interface descriptors and endpoint descriptors.
const DescReader = struct {
    buf: []u8,
    p: [*]u8,

    /// Create a new descriptor reader.
    pub fn new(buf: []u8) DescReader {
        return DescReader{ .buf = buf, .p = buf.ptr };
    }

    /// Get the next descriptor.
    /// Note that the first descriptor is never returned.
    pub fn next(self: *DescReader) ?[*]u8 {
        self.p += self.p[0];
        if (@intFromPtr(self.p) >= @intFromPtr(self.buf.ptr) + self.buf.len) {
            return null;
        } else {
            return self.p[0..];
        }
    }
};
