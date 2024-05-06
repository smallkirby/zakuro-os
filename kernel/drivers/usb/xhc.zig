//! This module provides a xHC (Entended Host Controller) driver.

const std = @import("std");
const zakuro = @import("zakuro");
const log = std.log.scoped(.xhci);
const arch = zakuro.arch;
const context = @import("context.zig");
const ring = @import("ring.zig");
const Trb = @import("trb.zig").Trb;
const DeviceContext = context.DeviceContext;

pub const XhcError = error{
    NoMemory,
};

/// Maximum number of device slots supported by this driver.
const num_device_slots = 8;
/// Buffer for device contexts.
/// TODO: replace this with a more dynamic allocation, then remove this global var.
var device_contexts: [num_device_slots + 1]DeviceContext = undefined;
/// Buffer for DCBAA.
/// TODO: replace this with a more dynamic allocation, then remove this global var.
var dcbaa: [num_device_slots + 1]u64 = undefined;

/// Buffer used by fixed-size allocator.
/// TODO: use kernel allocator whin it's ready.
var general_buf = [_]u8{0} ** (4096 * 10);
/// TODO: use kernel allocator whin it's ready.
var fsa = std.heap.FixedBufferAllocator.init(&general_buf);

/// xHCI Capability Registers.
const CapabilityRegisters = packed struct {
    /// Offset from register base to the Operational Register Space.
    cap_length: u8,
    /// Reserved
    _reserved: u8,
    /// BCD encoding of the xHCI spec revision number supported by this HC.
    hci_version: u16,
    /// HC Structural Parameters 1.
    hcs_params1: StructuralParameters1,
    /// HC Structural Parameters 2.
    hcs_params2: u32,
    /// HC Structural Parameters 3.
    hcs_params3: u32,
    /// HC Capability Parameters 1.
    hcc_params1: u32,
    /// Doorbell Array Offset.
    dboff: u32,
    /// Runtime Register Space Offset.
    rtsoff: u32,
    /// HC Capability Parameters 2.
    hcc_params2: u32,
};

/// xHC Operational Registers.
const OperationalRegisters = packed struct {
    /// USB Command.
    usbcmd: CommandRegister,
    /// USB Status.
    usbsts: StatusRegister,
    /// Page Size.
    pagesize: u32,
    /// Reserved.
    _reserved1: u64,
    /// Device Notification Control.
    dnctrl: u32,
    /// Command Ring Control,
    crcr: u64,
    /// Reserved.
    _reserved2: u128,
    /// Device Context Base Address Array Pointer.
    dcbaap: u64,
    /// Configure.
    config: ConfigureRegister,
};

/// USB Command Register. (USBCMD)
const CommandRegister = packed struct(u32) {
    /// Run/Stop.
    /// When set to 1, the xHC proceeds with execution of the schedule.
    /// When set to 0, the xHC completes the current transaction and halts.
    rs: bool,
    /// Host Controller Reset.
    hc_rst: bool,
    /// Interrupt Enable.
    inte: bool,
    /// Host System Error Enable,
    hsee: bool,
    /// Reserved
    _reserved1: u3,
    /// Light Host Controller Reset.
    lhcrst: bool,
    /// Controller Save State.
    css: bool,
    /// Controller Restore State.
    crs: bool,
    /// Enable Wrap Event.
    ewe: bool,
    /// Enable U3 MFINDEX Stop.
    ue3s: bool,
    /// Reserved.
    _reserved2: bool,
    /// CEM Enable.
    cme: bool,
    /// Extended TBC Enable.
    ete: bool,
    /// Extended TBC TRB Status Enable.
    tsc_en: bool,
    /// VTIO Enable.
    vtioe: bool,
    /// Reserved.
    _reserved3: u15,
};

/// USB Status Register. (USBSTS)
pub const StatusRegister = packed struct(u32) {
    /// HCHalted.
    hch: bool,
    /// Reserved.
    _reserved1: u1,
    /// Host System Error.
    hse: bool,
    /// Event Interrupt.
    eint: bool,
    /// Port Change Detect.
    pcd: bool,
    /// Reserved.
    _reserved2: u3,
    /// Save State Status.
    sss: bool,
    /// Restore State Status.
    rss: bool,
    /// Save/Restore Error.
    sre: bool,
    /// Controller Not Ready.
    cnr: bool,
    /// Host Controller Error.
    hce: bool,
    /// Reserved.
    _reserved3: u19,
};

/// Runtime xHC configuration register. (CONFIG)
const ConfigureRegister = packed struct(u32) {
    /// Number of Device Slots Enabled.
    max_slots_en: u8,
    /// U3 Entry Enable.
    u3e: bool,
    /// Configuration Information Enable.
    cie: bool,
    /// Reserved.
    _reserved: u22,
};

/// xHC Runtime Registers.
/// Actually, 1024 entries of Interrupter Register Set continues after this,
/// but we don't declare them here.
const RuntimeRegisters = packed struct(u256) {
    /// MFINDEX
    mfindex: u32,
    /// Reserved.
    _reserved: u224,
};

/// xHC Doorbell Register.
const DoorbellRegister = packed struct(u32) {
    /// Doorbell Target.
    db_target: u8,
    /// Reserved.
    _reserved: u8,
    /// Doorbell Stream ID.
    db_stream_id: u16,
};

/// HCSPARAMS1
const StructuralParameters1 = packed struct(u32) {
    /// Number of device slots.
    maxslots: u8,
    /// Number of interrupters.
    maxintrs: u11,
    /// Reserved.
    _reserved: u5,
    /// Number of ports.
    maxports: u8,
};

/// Interrupt Register Set in the xHC's Runtime Registers.
const InterrupterRegisterSet = packed struct(u256) {
    /// Interrupter Management Register.
    iman: InterrupterManagementRegister,
    /// Interrupter Moderation Register.
    imod: InterrupterModerationRegister,
    /// Event Ring Register.
    err: EventRingRegister,
};

/// Event Ring Register.
const EventRingRegister = packed struct(u192) {
    /// Event Ring Segment Table Size Register.
    erstsz: u32,
    /// Reserved.
    _reserved: u32,
    /// Event Ring Segment Table Base Address Register.
    erstba: u64,
    /// Event Ring Dequeue Pointer Register.
    /// TODO: 3 LSBs are used as DESI and EHB.
    erdp: u64,
};

/// Interrupter Management Register (IMAN) that allows system software to enable, disable, and detect xHC interrupts.
const InterrupterManagementRegister = packed struct(u32) {
    /// Interrupt Pending (IP)
    ip: bool,
    /// Interrupt Enable (IE)
    ie: bool,
    /// Reserved.
    _reserved: u30,
};

/// Interrupter Moderation Register (IMOD) that controls the moderation feature of an Interrupter.
const InterrupterModerationRegister = packed struct(u32) {
    /// Interrupter Moderation Interval, in 250ns increments (IMODI).
    imodi: u16,
    /// Reserved.
    _reserved: u16,
};

/// xHC Host Controller
pub const Controller = struct {
    /// MMIO base of the HC.
    /// This value can be calculated from BAR1:BAR:0.
    mmio_base: u64,
    /// Capability Registers.
    capability_regs: *volatile CapabilityRegisters,
    /// Operational Registers.
    operational_regs: *volatile OperationalRegisters,
    /// Runtime Registers.
    runtime_regs: *volatile RuntimeRegisters,
    /// Doorbell Registers.
    doorbell_regs: *volatile [256]DoorbellRegister,

    /// Device contexts.
    device_contexts: *[num_device_slots]DeviceContext = undefined,
    /// DCBAA: Device Context Base Address Array.
    /// TODO: should be dynamically allocated
    dcbaa: *[num_device_slots + 1]u64 = undefined,

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
        const capability_regs: *volatile CapabilityRegisters = @ptrFromInt(mmio_base);
        const operational_regs: *volatile OperationalRegisters = @ptrFromInt(mmio_base + capability_regs.cap_length);
        const runtime_regs: *volatile RuntimeRegisters = @ptrFromInt(mmio_base + capability_regs.rtsoff);
        const doorbell_regs: *volatile [256]DoorbellRegister = @ptrFromInt(mmio_base + capability_regs.dboff);
        log.debug("xHC Capability Registers @ {X:0>16}", .{@intFromPtr(capability_regs)});
        log.debug("xHC Operational Registers @ {X:0>16}", .{@intFromPtr(operational_regs)});
        log.debug("xHC Runtime Registers @ {X:0>16}", .{@intFromPtr(runtime_regs)});
        log.debug("xHC Doorbell Registers @ {X:0>16}", .{@intFromPtr(doorbell_regs)});

        const allocator = fsa.allocator();

        return Self{
            .mmio_base = mmio_base,
            .capability_regs = capability_regs,
            .operational_regs = operational_regs,
            .runtime_regs = runtime_regs,
            .doorbell_regs = doorbell_regs,
            .device_contexts = device_contexts[0..num_device_slots],
            .dcbaa = dcbaa[0 .. num_device_slots + 1],
            .cmd_ring = ring.Ring{},
            .event_ring = ring.EventRing{},
            .allocator = allocator,
        };
    }

    /// Reset the xHC.
    pub fn reset(self: Self) void {
        var cmd = self.operational_regs.usbcmd;

        // Disable interrupts and stop the controller.
        cmd.inte = false;
        cmd.hsee = false;
        cmd.ewe = false;
        if (!self.operational_regs.usbsts.hch) {
            cmd.rs = false;
        }
        self.operational_regs.usbcmd = cmd;

        // Wait for the controller to stop.
        while (!self.operational_regs.usbsts.hch) {
            arch.relax();
        }

        // Reset
        self.operational_regs.usbcmd.hc_rst = true;
        while (self.operational_regs.usbcmd.hc_rst != false) {
            arch.relax();
        }
        while (self.operational_regs.usbsts.cnr != false) {
            arch.relax();
        }
    }

    /// Initialize the xHC.
    pub fn init(self: *Self) XhcError!void {
        // Reset the controller.
        self.reset();

        // Set the number of device contexts.
        const max_slots = self.capability_regs.hcs_params1.maxslots;
        if (max_slots <= num_device_slots) {
            @panic("xHC does not support the required number of device slots");
        }
        self.operational_regs.config.max_slots_en = num_device_slots;
        log.debug("Set the num of device contexts to {d} (max: {d})", .{ num_device_slots, max_slots });

        // Clear DCBAA
        for (0..num_device_slots + 1) |i| {
            self.dcbaa[i] = 0;
        }

        // Set DCBAAP
        // TODO: DCBAAP should be aligned?
        self.operational_regs.dcbaap = @intFromPtr(&self.dcbaa);

        const num_trbs = 32;

        // Create TRB for Command Ring and set the ring to CRCR.
        self.cmd_ring.trbs = self.allocator.alignedAlloc(Trb, 0x1000, num_trbs) catch |err| {
            log.err("Failed to allocate TRBs for Command Ring: {?}", .{err});
            return XhcError.NoMemory;
        };
        @memset(@as([*]u8, @ptrCast(self.cmd_ring.trbs.ptr))[0..num_trbs], 0);
        self.operational_regs.crcr = @intFromPtr(self.cmd_ring.trbs.ptr) | @as(u64, @intCast(self.cmd_ring.pcs));

        // Create TRB and ERST for Event Ring and set the ring to primary interrupter.
        // We prepare only the primary interrupter.
        // We use only one segment here.
        self.event_ring.trbs = self.allocator.alignedAlloc(Trb, 4096, num_trbs) catch |err| {
            log.err("Failed to allocate TRBs for Event Ring: {?}", .{err});
            return XhcError.NoMemory;
        };
        @memset(@as([*]u8, @ptrCast(self.event_ring.trbs.ptr))[0..num_trbs], 0);

        self.event_ring.erst = self.allocator.alignedAlloc(ring.EventRingSegmentTableEntry, 4096, 1) catch |err| {
            log.err("Failed to allocate ERST for Event Ring: {?}", .{err});
            return XhcError.NoMemory;
        };
        @memset(@as([*]u8, @ptrCast(self.event_ring.erst.ptr))[0..1], 0);
        self.event_ring.erst[0].ring_segment_base_addr = @intFromPtr(self.event_ring.trbs.ptr);
        self.event_ring.erst[0].size = num_trbs;
        const primary_interrupter: *volatile InterrupterRegisterSet = self.getPrimaryInterrupter();
        primary_interrupter.err.erstsz = 1;
        primary_interrupter.err.erdp = (@intFromPtr(self.event_ring.trbs.ptr) & ~@as(u64, 0b111)) | (primary_interrupter.err.erdp & 0b111);
        primary_interrupter.err.erstba = @intFromPtr(self.event_ring.erst.ptr);

        // Enable interrupts
        // TODO: should write at once?
        primary_interrupter.imod.imodi = 4000;
        primary_interrupter.iman.ip = true;
        primary_interrupter.iman.ie = true;
        self.operational_regs.usbcmd.inte = true;
    }

    /// Get the array of interrupter registers in the xHC's Runtime Registers.
    fn getInterrupterRegisterSet(self: Self) *volatile [256]InterrupterRegisterSet {
        const ptr = @as(u64, @intFromPtr(self.runtime_regs)) + @sizeOf(RuntimeRegisters);
        return @ptrFromInt(ptr);
    }

    /// Get the pointer to the primary interrupter.
    fn getPrimaryInterrupter(self: Self) *volatile InterrupterRegisterSet {
        return &self.getInterrupterRegisterSet()[0];
    }
};
