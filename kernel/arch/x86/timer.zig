//! x64 32-bit programmable local APIC timer.

const apic = @import("apic.zig");

/// Initialize LAPIC timer with default configuration.
/// Divider is set to 1.
pub fn init(vector: u8, initial: u32) void {
    @as(*volatile u32, @ptrFromInt(apic.divide_config_register)).* = @intFromEnum(DivideValue.By1);

    const lvt = Lvt{
        .vector = vector,
        .mode = TimerMode.Periodic,
    };
    @as(*volatile u32, @ptrFromInt(apic.lvt_timer_register)).* = @bitCast(lvt);

    @as(*volatile u32, @ptrFromInt(apic.initial_count_register)).* = initial;
}

/// The APIC timer frequency is the processor's bus clock or crystal clock freq
/// divided by the value of the Divide Configuration Register.
const DivideValue = enum(u4) {
    By2 = 0b0_0_00,
    By4 = 0b0_0_01,
    By8 = 0b0_0_10,
    By16 = 0b0_0_11,
    By32 = 0b1_0_00,
    By64 = 0b1_0_01,
    By128 = 0b1_0_10,
    By1 = 0b1_0_11,
};

/// Local Vector Table for timer.
const Lvt = packed struct(u32) {
    /// Interrupt vector number.
    /// Interrupt is delivered to the processor when the timer reaches 0.
    vector: u8,
    /// Reserved.
    _reserved1: u4 = 0,
    /// Delivery status.
    delivery_status: DeliveryStatus = .Idle,
    /// Reserved.
    _reserved2: u3 = 0,
    /// When set to true, the interrupt is masked by the processor for this timer.
    masked: bool = false,
    /// Timer mode.
    mode: TimerMode,
    _reserver3: u13 = 0,
};

const DeliveryStatus = enum(u1) {
    /// No activity for this interrupt source, or the previous one was delivered.
    Idle = 0,
    /// The interrupt has been delivered, but not accepted by the processor.
    SendPending = 1,
};

const TimerMode = enum(u2) {
    /// One-shot.
    OneShot = 0b00,
    /// Periodic.
    /// When the Current Count Register reaches 0, the value of Initial Count Register is reloaded.
    Periodic = 0b01,
    /// TSC-deadline.
    TscDeadline = 0b10,
};
