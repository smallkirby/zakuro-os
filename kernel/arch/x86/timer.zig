//! x64 32-bit programmable local APIC timer.

const std = @import("std");
const log = std.log.scoped(.x64timer);

const apic = @import("apic.zig");
const acpi = @import("acpi.zig");
const arch = @import("arch.zig");

/// Initial value of the APIC timer counter.
var initial_value: u32 = undefined;
/// Frequency of the Local APIC timer.
var lapic_timer_freq: u32 = undefined;

/// Timer tick frequency.
const timer_tick_freq: u32 = 100; // 100 Hz

/// Initialize LAPIC timer with default configuration.
/// After calling this function, the timer ticks at `timer_tick_freq` Hz,
/// and every tick generates an interrupt with the specified vector.
pub fn init(vector: u8, rsdp: *acpi.Rsdp) void {
    // Init ACPI PM timer.
    acpi.init(rsdp);

    // Measure the frequency of the APIC timer using ACPI PM timer.
    @as(*volatile u32, @ptrFromInt(apic.divide_config_register)).* = @intFromEnum(DivideValue.By1);
    const lvt = Lvt{
        .vector = vector,
        .mode = TimerMode.OneShot,
    };
    @as(*volatile u32, @ptrFromInt(apic.lvt_timer_register)).* = @bitCast(lvt);
    initial_value = 0xFFFF_FFFF;

    arch.disableIntr();
    {
        start();
        acpi.waitMilliSeconds(100);
        const elapsed_time = elapsed();
        stop();
        lapic_timer_freq = elapsed_time * 10;
        log.info("Local APIC timer initialized with frequency: {} Hz", .{lapic_timer_freq});
    }
    arch.enableIntr();

    // Configure the timer.
    @as(*volatile u32, @ptrFromInt(apic.divide_config_register)).* = @intFromEnum(DivideValue.By1);
    const lvt_periodic = Lvt{
        .vector = vector,
        .mode = TimerMode.Periodic,
    };
    @as(*volatile u32, @ptrFromInt(apic.lvt_timer_register)).* = @bitCast(lvt_periodic);
    initial_value = lapic_timer_freq / timer_tick_freq;
    @as(*volatile u32, @ptrFromInt(apic.initial_count_register)).* = initial_value;
}

inline fn start() void {
    @as(*volatile u32, @ptrFromInt(apic.initial_count_register)).* = initial_value;
}

inline fn stop() void {
    @as(*volatile u32, @ptrFromInt(apic.initial_count_register)).* = 0;
}

inline fn elapsed() u32 {
    return initial_value - @as(*volatile u32, @ptrFromInt(apic.current_count_register)).*;
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
