//! This module provides a xHC (Entended Host Controller) driver.

const std = @import("std");
const zakuro = @import("zakuro");
const log = std.log.scoped(.xhci);
const arch = zakuro.arch;
const context = @import("context.zig");
const ring = @import("ring.zig");
const port = @import("port.zig");
const trbs = @import("trb.zig");
const DevController = zakuro.drivers.usb.controller.Controller;
const mod_device = @import("device.zig");
const Trb = trbs.Trb;
const DeviceContext = context.DeviceContext;
const Regs = @import("register.zig");
const Register = zakuro.mmio.Register;
const usb = zakuro.drivers.usb;
const DeviceDescriptor = usb.descriptor.DeviceDescriptor;

pub const XhcError = error{
    /// Memory allocation failed.
    NoMemory,
    /// Invalid state of FSM.
    InvalidState,
    /// Invalid slot number is specified.
    InvalidSlot,
    /// xHC failed to process the Transfer.
    TransferFailed,
};

/// Maximum number of device slots supported by this driver.
const num_device_slots = 8;

/// Buffer used by fixed-size allocator.
/// TODO: use kernel allocator whin it's ready.
var general_buf = [_]u8{0} ** (4096 * 10);
/// TODO: use kernel allocator whin it's ready.
var fsa = std.heap.FixedBufferAllocator.init(&general_buf);

/// xHC Host Controller
pub const Controller = struct {
    /// MMIO base of the HC.
    /// This value can be calculated from BAR1:BAR:0.
    mmio_base: u64,
    /// Capability Registers.
    capability_regs: *volatile Regs.CapabilityRegisters,
    /// Operational Registers.
    operational_regs: *volatile Regs.OperationalRegisters,
    /// Runtime Registers.
    runtime_regs: *volatile Regs.RuntimeRegisters,
    /// Doorbell Registers.
    doorbell_regs: *volatile [256]Register(Regs.DoorbellRegister, .DWORD),

    /// Device controller.
    dev_controller: DevController,

    /// Fixed-size allocator.
    /// TODO: use kernel allocator when it's ready.
    allocator: std.mem.Allocator,

    /// Comamnd Ring.
    cmd_ring: ring.Ring,
    /// Event Ring.
    event_ring: ring.EventRing,

    /// Port index under reset.
    port_under_reset: ?usize = null,
    /// Port State
    port_states: [256]port.PortState = [_]port.PortState{.Disconnected} ** 256,

    const Self = @This();

    /// Instantiate new handler of the xHC.
    pub fn new(mmio_base: u64) Self {
        // Calculate the address of the registers.
        const capability_regs: *volatile Regs.CapabilityRegisters = @ptrFromInt(mmio_base);
        const operational_regs: *volatile Regs.OperationalRegisters = @ptrFromInt(mmio_base + capability_regs.cap_length);
        const runtime_regs: *volatile Regs.RuntimeRegisters = @ptrFromInt(mmio_base + capability_regs.rtsoff & ~@as(u64, 0b11111));
        const doorbell_regs: *volatile [256]Register(Regs.DoorbellRegister, .DWORD) = @ptrFromInt(mmio_base + capability_regs.dboff);
        log.debug("xHC Capability Registers @ {X:0>16}", .{@intFromPtr(capability_regs)});
        log.debug("xHC Operational Registers @ {X:0>16}", .{@intFromPtr(operational_regs)});
        log.debug("xHC Runtime Registers @ {X:0>16}", .{@intFromPtr(runtime_regs)});
        log.debug("xHC Doorbell Registers @ {X:0>16}", .{@intFromPtr(doorbell_regs)});

        const allocator = fsa.allocator();

        // Init device controlle
        const dev_controller = DevController.new(8, allocator) catch |err| {
            log.err("Failed to initialize Device Controller: {?}", .{err});
            @panic("Failed to initialize Device Controller");
        };

        return Self{
            .mmio_base = mmio_base,
            .capability_regs = capability_regs,
            .operational_regs = operational_regs,
            .runtime_regs = runtime_regs,
            .doorbell_regs = doorbell_regs,
            .cmd_ring = ring.Ring{},
            .event_ring = ring.EventRing{},
            .allocator = allocator,
            .dev_controller = dev_controller,
        };
    }

    /// Reset the xHC.
    pub fn reset(self: *Self) void {
        // Disable interrupts and stop the controller.
        var cmd = self.operational_regs.usbcmd.read();
        cmd.inte = false;
        cmd.hsee = false;
        cmd.ewe = false;
        if (!self.operational_regs.usbsts.read().hch) {
            cmd.rs = false;
        }
        self.operational_regs.usbcmd.write(cmd);

        // Wait for the controller to stop.
        while (!self.operational_regs.usbsts.read().hch) {
            arch.relax();
        }

        // Reset
        self.operational_regs.usbcmd.modify(.{
            .hc_rst = true,
        });
        while (self.operational_regs.usbcmd.read().hc_rst) {
            arch.relax();
        }
        while (self.operational_regs.usbsts.read().cnr) {
            arch.relax();
        }
    }

    /// Initialize the xHC.
    pub fn init(self: *Self) XhcError!void {
        // Reset the controller.
        self.reset();
        log.debug("xHC Reset Complete", .{});

        // Set the number of device contexts.
        const max_slots = self.capability_regs.hcs_params1.read().maxslots;
        if (max_slots <= num_device_slots) {
            @panic("xHC does not support the required number of device slots");
        }
        self.operational_regs.config.modify(.{ .max_slots_en = num_device_slots });
        log.debug("Set the num of device contexts to {d} (max: {d})", .{ num_device_slots, max_slots });

        // Set DCBAAP
        self.operational_regs.dcbaap = @intFromPtr(self.dev_controller.dcbaa.ptr) & ~@as(u64, 0b111111);
        log.debug("DCBAAP Set to: {X:0>16}", .{self.operational_regs.dcbaap});

        const num_trbs = 32;

        // Create TRB for Command Ring and set the ring to CRCR.
        self.cmd_ring.trbs = self.allocator.alignedAlloc(Trb, 0x1000, num_trbs) catch |err| {
            log.err("Failed to allocate TRBs for Command Ring: {?}", .{err});
            return XhcError.NoMemory;
        };
        log.debug("Command Ring TRBs @ {X:0>16}", .{@intFromPtr(self.cmd_ring.trbs.ptr)});
        @memset(@as([*]u8, @ptrCast(self.cmd_ring.trbs.ptr))[0 .. num_trbs * @sizeOf(Trb)], 0);
        self.operational_regs.crcr = @intFromPtr(self.cmd_ring.trbs.ptr) | @as(u64, @intCast(self.cmd_ring.pcs));

        // Create TRB and ERST for Event Ring and set the ring to primary interrupter.
        // We prepare only the primary interrupter.
        // We use only one segment here.
        self.event_ring.trbs = self.allocator.alignedAlloc(Trb, 4096, num_trbs) catch |err| {
            log.err("Failed to allocate TRBs for Event Ring: {?}", .{err});
            return XhcError.NoMemory;
        };
        log.debug("Event Ring TRBs @ {X:0>16}", .{@intFromPtr(self.event_ring.trbs.ptr)});
        @memset(@as([*]u8, @ptrCast(self.event_ring.trbs.ptr))[0 .. num_trbs * @sizeOf(Trb)], 0);

        self.event_ring.erst = @ptrCast(self.allocator.alignedAlloc(ring.EventRingSegmentTableEntry, 4096, 1) catch |err| {
            log.err("Failed to allocate ERST for Event Ring: {?}", .{err});
            return XhcError.NoMemory;
        });
        log.debug("Event Ring ERST @ {X:0>16}", .{@intFromPtr(self.event_ring.erst.ptr)});
        @memset(@as([*]u8, @ptrCast(self.event_ring.erst.ptr))[0 .. 1 * @sizeOf(ring.EventRingSegmentTableEntry)], 0);
        self.event_ring.erst[0].ring_segment_base_addr = @intFromPtr(self.event_ring.trbs.ptr);
        self.event_ring.erst[0].size = num_trbs;

        const primary_interrupter: *volatile Regs.InterrupterRegisterSet = self.getPrimaryInterrupter();
        var new_interrupter = primary_interrupter.*;
        new_interrupter.erstsz = 1;
        new_interrupter.erdp = (@intFromPtr(self.event_ring.trbs.ptr) & ~@as(u64, 0b111)) | (primary_interrupter.erdp & 0b111);
        new_interrupter.erstba = @intFromPtr(self.event_ring.erst.ptr);
        primary_interrupter.* = new_interrupter;
        self.event_ring.interrupter = primary_interrupter;

        // Enable interrupts
        new_interrupter = primary_interrupter.*;
        new_interrupter.imod.modify(.{
            .imodi = 4000,
        });
        new_interrupter.iman.modify(.{
            .ip = true,
            .ie = true,
        });
        primary_interrupter.* = new_interrupter;

        self.operational_regs.usbcmd.modify(.{
            .inte = true,
        });
    }

    /// Start running the xHC.
    pub fn run(self: *Self) void {
        self.operational_regs.usbcmd.modify(.{
            .rs = true,
        });

        while (self.operational_regs.usbsts.read().hch) {
            arch.relax();
        }
    }

    /// Get the array of interrupter registers in the xHC's Runtime Registers.
    fn getInterrupterRegisterSet(self: Self) *volatile [256]Regs.InterrupterRegisterSet {
        const ptr = @as(u64, @intFromPtr(self.runtime_regs)) + @sizeOf(Regs.RuntimeRegisters);
        return @ptrFromInt(ptr);
    }

    /// Get the pointer to the primary interrupter.
    fn getPrimaryInterrupter(self: Self) *volatile Regs.InterrupterRegisterSet {
        return &self.getInterrupterRegisterSet()[0];
    }

    /// Get the multi-items pointers of Port Register Set.
    fn getPortRegisterSet(self: Self) [*]Regs.PortRegisterSet {
        const ptr = @as(u64, @intFromPtr(self.operational_regs)) + 0x400;
        return @ptrFromInt(ptr);
    }

    /// Get the pointer to the Port Register Set at the specified index.
    /// Note that port_index is 1-origin.
    pub fn getPortAt(self: *Self, port_index: usize) port.Port {
        const prs = &self.getPortRegisterSet()[port_index - 1];
        return port.Port.new(port_index, prs);
    }

    /// Check if HCE(Host Controller Error) is asserted.
    fn checkError(self: *Self) void {
        if (self.operational_regs.usbsts.read().hce) {
            log.err("HCE is set.", .{});
        }
    }

    /// Find a port that waits to be addressed and start addressing it.
    fn schedulePort(self: *Self) XhcError!void {
        if (self.port_under_reset != null) {
            return;
        }
        for (0.., self.port_states) |i, state| {
            if (state == .WaitingAddressed) {
                const prt = self.getPortAt(i);
                try self.resetPort(prt);
                break;
            }
        }
    }

    /// Process an event queued in the Event Ring.
    pub fn processEvent(self: *Self) !void {
        self.checkError();

        if (!self.event_ring.hasEvent()) {
            return;
        }

        const trb = self.event_ring.front();
        try switch (trb.trb_type) {
            .Reserved => log.warn("TRB with Reserved Type is enqueued in the Event Ring.", .{}),
            .PortStatusChange => self.onPortStatusChangeEvent(@ptrCast(trb)),
            .CommandCompletion => self.onCommandCompleteEvent(@ptrCast(trb)),
            .Transfer => onTransfer(self, @ptrCast(trb)),
            else => log.warn("Unsupported TRB Type is enqueued in the Event Ring.", .{}),
        };
        self.event_ring.pop();
    }

    /// Assign an address to the device.
    fn addressDevice(self: *Self, port_id: usize, slot_id: usize) XhcError!void {
        log.debug("Addressing the device: port_id={d}, slot_id={d}", .{ port_id, slot_id });

        // Allocate a device in the slot.
        self.dev_controller.allocateDevice(
            slot_id,
            &self.doorbell_regs[slot_id],
            self.allocator,
        ) catch |err| {
            log.err("Failed to allocate a device in the slot: {?}", .{err});
            switch (err) {
                error.AllocationFailed => return XhcError.NoMemory,
                else => {
                    log.err("Unexpected error while addressing a device: {?}", .{err});
                    @panic("Aborting...");
                },
            }
        };

        const device = &self.dev_controller.devices[slot_id].?.dev;
        device.input_context.clearIcc();

        // Enable Slot Context and Endpoint 0 Context.
        const ep0_dci = mod_device.calcDci(0, .InOut);
        device.input_context.icc.add_context_flag |= 0b1; // Enable Slot Context.
        device.input_context.icc.add_context_flag |= @as(u32, 0b1) << ep0_dci; // Enable Endpoint 0 Context.

        // Initialize Slot Context.
        const prt = self.getPortAt(port_id);
        const sc = &device.input_context.sc;
        sc.route_string = 0;
        sc.root_hub_port_num = @truncate(port_id);
        sc.context_entries = 1;
        sc._speed = prt.prs.portsc.read().speed;

        // Initialize Endpoint 0 Context.
        const transfer_ring = device.allocTransferRing(
            ep0_dci,
            32,
            self.allocator,
        );
        const epctx = &device.input_context.endpoint_context[0];
        epctx.ep_type = 4; // TODO: docs
        epctx.max_packet_size = mod_device.calcMaxPacketSize(sc._speed);
        epctx.max_burst_size = 0;
        epctx.interval = 0;
        epctx.max_pstreams = 0;
        epctx.mult = 0;
        epctx.cerr = 3; // TODO: docs
        epctx.dcs = 1; // TODO: docs
        epctx.tr_dequeue_pointer = @truncate(@intFromPtr(transfer_ring.trbs.ptr) >> 4);

        // Record the device context.
        self.dev_controller.dcbaa[slot_id] = &device.device_context;

        self.port_states[port_id] = .Addressing;

        // Notify the xHC to address the device.
        var adc_trb = trbs.AddressDeviceCommandTrb{
            .slot_id = @truncate(slot_id),
            .input_context_pointer = @intFromPtr(&device.input_context),
        };
        _ = self.cmd_ring.push(@ptrCast(&adc_trb));
        self.notify_doorbell(0);
        log.debug("Notified the xHC to address the device.", .{});
    }

    /// Initialize the USB device at the specified port and slot.
    fn initializeUsbDevice(self: *Self, port_id: usize, slot_id: usize) !void {
        const device = self.dev_controller.devices[slot_id] orelse {
            return XhcError.InvalidSlot;
        };
        self.port_states[port_id] = .InitializingDevice;
        try device.start_device_init();
    }

    /// Handle an Transfer Event.
    fn onTransfer(
        self: *Self,
        trb: *volatile trbs.TransferEventTrb,
    ) !void {
        const slot_id = trb.slot_id;
        const dev = self.dev_controller.devices[slot_id] orelse return XhcError.InvalidSlot;

        // Check if the completion code is valid.
        switch (trb.completion_code) {
            1, 13 => {},
            else => return XhcError.TransferFailed,
        }

        try dev.onTransferEventReceived(trb);

        // TODO: unimplemented: start config of the device after initialization.
    }

    /// Handle an Command Completion Event.
    fn onCommandCompleteEvent(
        self: *Self,
        trb: *volatile trbs.CommandCompletionEventTrb,
    ) !void {
        const cmd_trb: *Trb = @ptrFromInt(trb.command_trb_pointer);
        const issuer_type = cmd_trb.trb_type;
        const slot_id = trb.slot_id;
        log.debug("Command Completion Event: slot_id={d}, issuer_type={?}", .{ slot_id, issuer_type });

        switch (issuer_type) {
            .EnableSlotCommand => {
                if (self.port_under_reset == null or self.port_states[self.port_under_reset.?] != .EnablingSlot) {
                    log.err(
                        "Invalid port state when Enable Slot Command is completed: index={d}, current={?}",
                        .{ slot_id, self.port_states[slot_id] },
                    );
                    return XhcError.InvalidState;
                }
                try self.addressDevice(self.port_under_reset.?, slot_id);
            },
            .AddressDeviceCommand => {
                const device = self.dev_controller.devices[slot_id] orelse {
                    return XhcError.InvalidSlot;
                };
                const port_id = device.dev.device_context.slot_context.root_hub_port_num;
                if (port_id != self.port_under_reset) {
                    return XhcError.InvalidState;
                }
                if (self.port_states[port_id] != .Addressing) {
                    return XhcError.InvalidState;
                }

                self.port_under_reset = null;
                try self.schedulePort();

                try self.initializeUsbDevice(port_id, slot_id);
            },
            else => {
                log.err("Unsupported TRB command is completed.", .{});
                return XhcError.InvalidState;
            },
        }
    }

    /// Handle an Port Status Change Event.
    fn onPortStatusChangeEvent(
        self: *Self,
        trb: *volatile trbs.PortStatusChangeEventTrb,
    ) XhcError!void {
        const port_id = trb.port_id;
        const target_port = self.getPortAt(port_id);
        log.debug("Port Status Change Event: port_id={d}, status={?}", .{ port_id, self.port_states[port_id] });

        try switch (self.port_states[port_id]) {
            .Disconnected => self.resetPort(target_port),
            .Resetting => self.enableSlot(target_port),
            else => {
                log.err(
                    "Port status invalid while the port status change event is received: index={d}, current={?}",
                    .{ port_id, self.port_states[port_id] },
                );
                return XhcError.InvalidState;
            },
        };
    }

    /// Enable the slot.
    fn enableSlot(self: *Self, prt: port.Port) void {
        const enabled = prt.isEnabled();
        const reset_changed = prt.isResetChanged();
        if (!enabled or !reset_changed) {
            return;
        }
        log.debug("Enabling the port: {d}", .{prt.port_index});

        // Clear status change bit
        prt.prs.portsc.modify(.{
            .csc = true,
        });
        self.port_states[prt.port_index] = .EnablingSlot;

        // Issue Enable Slot Command
        var esc_trb = trbs.EnableSlotCommandTrb{};
        _ = self.cmd_ring.push(@ptrCast(&esc_trb));
        self.notify_doorbell(0);
    }

    /// Reset the port.
    pub fn resetPort(self: *Self, prt: port.Port) XhcError!void {
        const sc = prt.prs.portsc.read();
        // If the port is not connected, we cannot reset it.
        if (!sc.ccs) {
            return;
        }

        // If other port is under reset, we cannot reset it.
        if (self.port_under_reset != null) {
            self.port_states[prt.port_index] = .WaitingAddressed;
            return;
        }

        // Reset the port if the state is valid.
        switch (self.port_states[prt.port_index]) {
            .Disconnected,
            .WaitingAddressed,
            => {
                self.port_under_reset = prt.port_index;
                self.port_states[prt.port_index] = .Resetting;
                prt.reset();
            },
            else => return XhcError.InvalidState,
        }
    }

    /// Notify to the xHC by setting the doorbell register.
    fn notify_doorbell(self: *Self, target: u8) void {
        self.doorbell_regs[target].write(Regs.DoorbellRegister{
            .db_stream_id = 0,
            .db_target = target,
        });
    }
};

////////////////////////////////////////

const expectEqual = std.testing.expectEqual;

test "xHC Controller Register Access" {
    const allocator = std.heap.page_allocator;
    const memory = try allocator.alloc(u8, 0x3000);
    defer allocator.free(memory);
    const base: u64 = @intFromPtr(memory.ptr);
    try expectEqual(base & 0xFFF, 0);

    const capability_regs: *volatile Regs.CapabilityRegisters = @ptrFromInt(base);
    capability_regs.cap_length = 0x40;
    capability_regs.rtsoff = 0x1000;
    capability_regs.dboff = 0x2000;
    const operational_regs: *volatile Regs.OperationalRegisters = @ptrFromInt(base + capability_regs.cap_length);
    const runtime_regs: *volatile Regs.RuntimeRegisters = @ptrFromInt(base + capability_regs.rtsoff & ~@as(u64, 0b11111));

    // Test register addresses
    var hc = Controller.new(@intFromPtr(memory.ptr));
    try expectEqual(capability_regs, hc.capability_regs);
    try expectEqual(operational_regs, hc.operational_regs);
    try expectEqual(runtime_regs, hc.runtime_regs);

    // Test USB Command Register
    hc.operational_regs.usbcmd._data.css = true;
    hc.operational_regs.usbcmd._data.hc_rst = true;
    hc.operational_regs.usbcmd._data.rs = false;
    hc.operational_regs.usbcmd._data.inte = true;
    const cmd = hc.operational_regs.usbcmd.read();
    try expectEqual(cmd.css, true);
    try expectEqual(cmd.hc_rst, true);
    try expectEqual(cmd.rs, false);
    try expectEqual(cmd.inte, true);

    // Test USB Status Register
    hc.operational_regs.usbsts._data.hch = true;
    hc.operational_regs.usbsts._data.hse = true;
    hc.operational_regs.usbsts._data.pcd = false;
    const status = hc.operational_regs.usbsts.read();
    try expectEqual(status.hch, true);
    try expectEqual(status.hse, true);
    try expectEqual(status.pcd, false);

    // Test HCSPARAMS1 Register
    hc.capability_regs.hcs_params1._data.maxslots = 0x10;
    try expectEqual(0x10, hc.capability_regs.hcs_params1.read().maxslots);
}
