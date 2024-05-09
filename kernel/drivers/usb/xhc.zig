//! This module provides a xHC (Entended Host Controller) driver.

const std = @import("std");
const zakuro = @import("zakuro");
const log = std.log.scoped(.xhci);
const arch = zakuro.arch;
const context = @import("context.zig");
const ring = @import("ring.zig");
const port = @import("port.zig");
const Trb = @import("trb.zig").Trb;
const DeviceContext = context.DeviceContext;
const Regs = @import("register.zig");
const Register = zakuro.mmio.Register;

pub const XhcError = error{
    NoMemory,
};

/// Maximum number of device slots supported by this driver.
const num_device_slots = 8;
/// Buffer for device contexts.
/// TODO: replace this with a more dynamic allocation, then remove this global var.
var device_contexts: [num_device_slots + 1]DeviceContext = undefined;

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
    doorbell_regs: *volatile [256]Regs.DoorbellRegister,

    /// Device contexts.
    device_contexts: *[num_device_slots]DeviceContext = undefined,
    /// DCBAA: Device Context Base Address Array.
    /// TODO: should be dynamically allocated
    dcbaa: []u64 = undefined,

    /// Fixed-size allocator.
    /// TODO: use kernel allocator when it's ready.
    allocator: std.mem.Allocator,

    /// Comamnd Ring.
    cmd_ring: ring.Ring,
    /// Event Ring.
    event_ring: ring.EventRing,

    const Self = @This();

    /// Instantiate new handler of the xHC.
    pub fn new(mmio_base: u64) Self {
        const capability_regs: *volatile Regs.CapabilityRegisters = @ptrFromInt(mmio_base);
        const operational_regs: *volatile Regs.OperationalRegisters = @ptrFromInt(mmio_base + capability_regs.cap_length);
        const runtime_regs: *volatile Regs.RuntimeRegisters = @ptrFromInt(mmio_base + capability_regs.rtsoff & ~@as(u64, 0b11111));
        const doorbell_regs: *volatile [256]Regs.DoorbellRegister = @ptrFromInt(mmio_base + capability_regs.dboff);
        log.debug("xHC Capability Registers @ {X:0>16}", .{@intFromPtr(capability_regs)});
        log.debug("xHC Operational Registers @ {X:0>16}", .{@intFromPtr(operational_regs)});
        log.debug("xHC Runtime Registers @ {X:0>16}", .{@intFromPtr(runtime_regs)});
        log.debug("xHC Doorbell Registers @ {X:0>16}", .{@intFromPtr(doorbell_regs)});

        const allocator = fsa.allocator();
        const dcbaa = allocator.alignedAlloc(u64, 0x100, num_device_slots + 1) catch |err| {
            log.err("Failed to allocate DCBAA: {?}", .{err});
            @panic("Failed to allocate DCBAA");
        };
        @memset(@as([*]u8, @ptrCast(dcbaa.ptr))[0 .. (num_device_slots + 1) * @sizeOf(u64)], 0);

        return Self{
            .mmio_base = mmio_base,
            .capability_regs = capability_regs,
            .operational_regs = operational_regs,
            .runtime_regs = runtime_regs,
            .doorbell_regs = doorbell_regs,
            .device_contexts = device_contexts[0..num_device_slots],
            .dcbaa = dcbaa,
            .cmd_ring = ring.Ring{},
            .event_ring = ring.EventRing{},
            .allocator = allocator,
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

        // Clear DCBAA
        for (0..num_device_slots + 1) |i| {
            self.dcbaa[i] = 0;
        }

        // Set DCBAAP
        // TODO: DCBAAP should be aligned?
        if ((@intFromPtr(self.dcbaa.ptr) & 0b111111) != 0) {
            @panic("DCBAAP is not aligned");
        }
        self.operational_regs.dcbaap = @intFromPtr(self.dcbaa.ptr) & ~@as(u64, 0b111111);
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

        self.event_ring.erst = self.allocator.alignedAlloc(ring.EventRingSegmentTableEntry, 4096, 1) catch |err| {
            log.err("Failed to allocate ERST for Event Ring: {?}", .{err});
            return XhcError.NoMemory;
        };
        log.debug("Event Ring ERST @ {X:0>16}", .{@intFromPtr(self.event_ring.erst.ptr)});
        @memset(@as([*]u8, @ptrCast(self.event_ring.erst.ptr))[0 .. 1 * @sizeOf(ring.EventRingSegmentTableEntry)], 0);
        self.event_ring.erst[0].ring_segment_base_addr = @intFromPtr(self.event_ring.trbs.ptr);
        self.event_ring.erst[0].size = num_trbs;

        const primary_interrupter: *volatile Regs.InterrupterRegisterSet = self.getPrimaryInterrupter();
        var new_interrupter = primary_interrupter.*;
        new_interrupter.err.erstsz = 1;
        new_interrupter.err.erdp = (@intFromPtr(self.event_ring.trbs.ptr) & ~@as(u64, 0b111)) | (primary_interrupter.err.erdp & 0b111);
        new_interrupter.err.erstba = @intFromPtr(self.event_ring.erst.ptr);
        primary_interrupter.* = new_interrupter;

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
