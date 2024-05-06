//! This module provides a xHC (Entended Host Controller) driver.

const std = @import("std");
const zakuro = @import("zakuro");
const log = std.log.scoped(.xhci);
const arch = zakuro.arch;

/// xHCI Capability Registers.
const CapabilityRegisters = packed struct {
    /// Offset from register base to the Operational Register Space.
    cap_length: u8,
    /// Reserved
    _reserved: u8,
    /// BCD encoding of the xHCI spec revision number supported by this HC.
    hci_version: u16,
    /// HC Structural Parameters 1.
    hcs_params1: u32,
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
    config: u32,
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

/// xHC Runtime Registers.
const RuntimeRegisters = packed struct {
    // TODO
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

/// xHC Host Controller
pub const Controller = struct {
    /// MMIO base of the HC.
    /// This value can be calculated from BAR1:BAR:0.
    mmio_base: u64,
    /// Capability Registers.
    capability_regs: *volatile CapabilityRegisters,
    /// Operational Registers.
    operationla_regs: *volatile OperationalRegisters,
    /// Runtime Registers.
    runtime_regs: *volatile RuntimeRegisters,
    /// Doorbell Registers.
    doorbell_regs: *volatile [256]DoorbellRegister,

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

        return Self{
            .mmio_base = mmio_base,
            .capability_regs = capability_regs,
            .operationla_regs = operational_regs,
            .runtime_regs = runtime_regs,
            .doorbell_regs = doorbell_regs,
        };
    }

    /// Reset the xHC.
    pub fn reset(self: Self) void {
        var cmd = self.operationla_regs.usbcmd;

        // Disable interrupts and stop the controller.
        cmd.inte = false;
        cmd.hsee = false;
        cmd.ewe = false;
        if (!self.operationla_regs.usbsts.hch) {
            cmd.rs = false;
        }
        self.operationla_regs.usbcmd = cmd;

        // Wait for the controller to stop.
        while (!self.operationla_regs.usbsts.hch) {
            arch.relax();
        }
    }

    /// Initialize the xHC.
    pub fn init(self: Self) void {
        self.reset();
    }
};
