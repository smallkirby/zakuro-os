//! This module provides a context structures for xHC.

const std = @import("std");
const PortSpeed = @import("register.zig").PortSpeed;

/// Device Context that is transferred to the xHC to report the state of a device.
/// TODO: Should be a packed or extern struct.
pub const InputContext = struct {
    /// Input Control Context.
    icc: InputControlContext,
    /// Slot Context. Entry 0.
    sc: SlotContext,
    endpoint_context: [31]EndpointContext,

    const Self = @This();

    comptime {
        if (@bitSizeOf(Self) != (32 * 8) * 33) {
            @compileError("Invalid size for DeviceContext");
        }
    }

    /// Clear Input Control Context.
    pub fn clearIcc(self: *Self) void {
        const ptr = std.mem.asBytes(&self.icc);
        @memset(ptr[0..@sizeOf(@TypeOf(self.icc))], 0);
    }

    /// Enable the endpoint.
    pub fn enableEndpoint(self: *Self, ctx_index: u32) *EndpointContext {
        self.icc.add_context_flag |= @as(u32, 1) << @as(u5, @truncate(ctx_index));
        return &self.endpoint_context[ctx_index - 1];
    }
};

/// Slot Context that defines entire configuration of the slot.
const SlotContext = packed struct(u256) {
    /// Route String that is used by hubs to route packets to the correct downstream port.
    route_string: u20,
    /// Deprecated.
    _speed: PortSpeed,
    /// Reserved.
    _reserved1: u1,
    /// Multi-TT.
    mtt: bool,
    /// Set to 1 if the device is a hub.
    hub: bool,
    /// Context Entries. Identifies the index of the last valid Endpoint Context within this Device Context.
    context_entries: u5,

    /// Max Exit Latency.
    max_exit_latency: u16,
    /// Root Hub Port Number.
    root_hub_port_num: u8,
    /// Number of Ports. Only used if the device is a hub.
    num_ports: u8,

    /// Parent Hub Slot ID.
    parent_hub_slotid: u8,
    /// Parent Port Number.
    parent_port_number: u8,
    /// TT Think Time.
    ttt: u2,
    /// Reserved.
    _reserved2: u4,
    /// Interrupter Target.
    interrupter_target: u10,

    /// USB Device Address.
    usb_device_addr: u8,
    /// Reserved.
    _reserved3: u19,
    /// Slot State.
    slot_state: u5,

    /// xHCI Reserved.
    _reserved4: u128,
};

/// Endpoint Context that defines information that applies to a single endpoint.
pub const EndpointContext = packed struct(u256) {
    /// Endponit State.
    ep_state: u3,
    /// Reserved.
    _reserved1: u5,
    /// Mult.
    mult: u2,
    /// Max Primary Streams.
    max_pstreams: u5,
    /// Linear Stream Array.
    lsa: u1,
    /// Interval.
    interval: u8,
    /// Max Endpoint Service Time Interval Payload High.
    max_esit_payload_hi: u8,

    /// Reserved.
    _reserved2: u1,
    /// Error Count.
    cerr: u2,
    /// Endpoint Type.
    ep_type: u3,
    /// Reserved.
    _reserved3: u1,
    /// Host Initiate Disable.
    hid: u1,
    /// Max Burst Size.
    max_burst_size: u8,
    /// Max Packet Size.
    max_packet_size: u16,

    /// Dequeue Cycle State.
    dcs: u1,
    /// Reserved.
    _reserved4: u3,
    /// TR Dequeue Pointer.
    tr_dequeue_pointer: u60,

    /// Average TRB Length.
    average_trb_length: u16,
    /// Max Endpoint Service Time Interval Payload Low.
    max_esit_payload_lo: u16,

    /// Reserved.
    _reserved5: u96 = undefined,
};

/// Input Control Context for Input Context.
const InputControlContext = packed struct(u256) {
    /// Drop Context Flags.
    drop_context_flag: u32,
    /// Add Context Flags.
    /// Determines entries in the Input Control Context should be evaluated.
    add_context_flag: u32,
    /// Reserved.
    _reserved1: u160 = 0,
    /// TODO
    configuration_value: u8,
    /// TODO
    interface_number: u8,
    /// TODO
    alternate_setting: u8,
    /// Reserved.
    _reserved2: u8 = 0,
};

/// TODO
pub const DeviceContext = struct {
    /// Slot Context.
    slot_context: SlotContext,
    /// Endpoint Contexts.
    endpoint_contexts: [31]EndpointContext,

    comptime {
        if (@bitSizeOf(DeviceContext) != (32 * 8) * 32) {
            @compileError("Invalid size for DeviceContext");
        }
    }
};
