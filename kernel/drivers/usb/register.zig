//! This file defines the xHCI registers.

const zakuro = @import("zakuro");
const Register = zakuro.mmio.Register;

/// xHCI Capability Registers.
pub const CapabilityRegisters = packed struct {
    /// Offset from register base to the Operational Register Space.
    cap_length: u8,
    /// Reserved
    _reserved: u8,
    /// BCD encoding of the xHCI spec revision number supported by this HC.
    hci_version: u16,
    /// HC Structural Parameters 1.
    hcs_params1: Register(StructuralParameters1, .DWORD),
    /// HC Structural Parameters 2.
    hcs_params2: u32,
    /// HC Structural Parameters 3.
    hcs_params3: u32,
    /// HC Capability Parameters 1.
    hcc_params1: Register(CapabilityParameters1, .DWORD),
    /// Doorbell Array Offset.
    dboff: u32,
    /// Runtime Register Space Offset.
    rtsoff: u32,
    /// HC Capability Parameters 2.
    hcc_params2: u32,
};

/// xHC Operational Registers.
/// Actually, Port Register Set continues at offset 0x400, but we don't declare them here.
pub const OperationalRegisters = packed struct {
    /// USB Command.
    usbcmd: Register(CommandRegister, .DWORD),
    /// USB Status.
    usbsts: Register(StatusRegister, .DWORD),
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
    config: Register(ConfigureRegister, .DWORD),
};

pub const PortRegisterSet = packed struct(u128) {
    /// Port Status and Control.
    portsc: Register(PortStatusControlRegister, .DWORD),
    /// Port Power Management Status and Control.
    portpmsc: u32,
    /// Port Link Info.
    portli: u32,
    /// Port Hardware LPM Control.
    porthlpmc: u32,
};

/// PORTSC. Can be used to determine how many ports need to be serviced.
const PortStatusControlRegister = packed struct(u32) {
    /// Current Connect Status.
    ccs: bool,
    /// Port Enabled/Disabled.
    ped: bool,
    /// Reserved.
    _reserved1: u1,
    /// Over-current Active.
    oca: bool,
    /// Port Reset.
    pr: bool,
    /// Port Link State.
    pls: u4,
    /// Port Power.
    pp: bool,
    /// Port Speed.
    speed: u4,
    /// Port Indicator Control.
    pic: u2,
    /// Port Link State Write Strobe.
    lws: bool,
    /// Connect Status Change.
    /// This bit is RW1CS (Sticky-Write-1-to-clear status).
    /// Writing 1 to this bit clears the status, and 0 has no effect.
    csc: bool,
    /// Port Enabled/Disabled Change.
    pec: bool,
    /// Warm Port Reset Change.
    wrc: bool,
    /// Over-current Change.
    occ: bool,
    /// Port Reset Change.
    prc: bool,
    /// Port Link State Change.
    plc: bool,
    /// Port Config Error Change.
    cec: bool,
    /// Cold Attach Status.
    cas: bool,
    /// Wake on Connect Enable.
    wce: bool,
    /// Wake on Disconnect Enable.
    wde: bool,
    /// Wake on Over-current Enable.
    woe: bool,
    /// Reserved.
    _reserved2: u2,
    /// Device Removable.
    dr: bool,
    /// Warm Port Reset.
    wpr: bool,
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
pub const RuntimeRegisters = packed struct(u256) {
    /// MFINDEX
    mfindex: u32,
    /// Reserved.
    _reserved: u224,
};

/// xHC Doorbell Register.
pub const DoorbellRegister = packed struct(u32) {
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

/// HCCPARAMS1
const CapabilityParameters1 = packed struct(u32) {
    /// Unimplemented
    _unimplemented: u16,
    /// xHCI Extended Capabilities Pointer.
    xecp: u16,
};

/// Interrupt Register Set in the xHC's Runtime Registers.
pub const InterrupterRegisterSet = packed struct(u256) {
    /// Interrupter Management Register.
    iman: Register(InterrupterManagementRegister, .DWORD),
    /// Interrupter Moderation Register.
    imod: Register(InterrupterModerationRegister, .DWORD),
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

////////////////////////////////////////

const std = @import("std");
const expectEqual = std.testing.expectEqual;

test "Test USB Command Register" {
    var ope = std.mem.zeroes(OperationalRegisters);
    try expectEqual(
        ope.usbcmd,
        std.mem.zeroes(Register(CommandRegister, .DWORD)),
    );

    // Test modify
    ope.usbcmd.modify(.{
        .inte = false,
        .hsee = true,
        .vtioe = true,
        .lhcrst = true,
    });
    const val = ope.usbcmd.read();
    try expectEqual(val.inte, false);
    try expectEqual(val.hsee, true);
    try expectEqual(val.vtioe, true);
    try expectEqual(val.lhcrst, true);
    // Test read
    try expectEqual(ope.usbcmd._data.inte, false);
    try expectEqual(ope.usbcmd._data.hsee, true);
    try expectEqual(ope.usbcmd._data.vtioe, true);
    try expectEqual(ope.usbcmd._data.lhcrst, true);

    // Test write
    var new_val = std.mem.zeroes(CommandRegister);
    new_val.inte = true;
    new_val.hsee = false;
    new_val.vtioe = true;
    new_val.lhcrst = false;
    ope.usbcmd.write(new_val);
    try expectEqual(ope.usbcmd.read().inte, true);
    try expectEqual(ope.usbcmd.read().hsee, false);
    try expectEqual(ope.usbcmd.read().vtioe, true);
    try expectEqual(ope.usbcmd.read().lhcrst, false);
}

test "Test USB Status Register" {
    var ope = std.mem.zeroes(OperationalRegisters);
    try expectEqual(
        ope.usbsts,
        std.mem.zeroes(Register(StatusRegister, .DWORD)),
    );

    // Test modify
    ope.usbsts.modify(.{
        .hch = true,
        .hse = false,
        .eint = true,
        .pcd = false,
    });
    const val = ope.usbsts.read();
    try expectEqual(val.hch, true);
    try expectEqual(val.hse, false);
    try expectEqual(val.eint, true);
    try expectEqual(val.pcd, false);
    // Test read
    try expectEqual(ope.usbsts._data.hch, true);
    try expectEqual(ope.usbsts._data.hse, false);
    try expectEqual(ope.usbsts._data.eint, true);
    try expectEqual(ope.usbsts._data.pcd, false);

    // Test write
    var new_val = std.mem.zeroes(StatusRegister);
    new_val.hch = false;
    new_val.hse = true;
    new_val.eint = false;
    new_val.pcd = true;
    ope.usbsts.write(new_val);
    try expectEqual(ope.usbsts.read().hch, false);
    try expectEqual(ope.usbsts.read().hse, true);
    try expectEqual(ope.usbsts.read().eint, false);
    try expectEqual(ope.usbsts.read().pcd, true);
}
