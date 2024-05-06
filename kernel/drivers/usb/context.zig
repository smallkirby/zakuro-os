//! This module provides a context structures for xHC.

/// Device Context that is transferred to the xHC to report the state of a device.
/// TODO: Should be a packed or extern struct.
pub const DeviceContext = struct {
    slot_context: SlotContext,
    endpoint_context: [31]EndpointContext,

    comptime {
        if (@bitSizeOf(DeviceContext) != (32 * 8) * 32) {
            @compileError("Invalid size for DeviceContext");
        }
    }
};

/// Slot Context that defines information that applies to a device as a whole.
pub const SlotContext = packed struct(u256) {
    /// Route String, used by hubs to route packets to the downstream port.
    route_string: u20,
    /// Speed. Deprecated.
    speed: u4,
    /// Reserved.
    _reserved1: u1,
    /// Multi-TT.
    mtt: bool,
    /// Hub. Software set to 1 if this device is a USB hub.
    hub: bool,
    /// Context Entries. The index of the last valid Endpoint Context within this Device Context.
    context_entries: u5,

    /// Max Exit Latency.
    max_exit_latency: u16,
    /// Root Hub Port Number.
    root_hub_port_number: u8,
    /// Number of Ports.
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
    _xhci_reserved: u128 = 0,

    comptime {
        if (@bitSizeOf(SlotContext) != 32 * 8) {
            @compileError("Invalid size for SlotContext");
        }
    }
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

    comptime {
        if (@bitSizeOf(EndpointContext) != 32 * 8) {
            @compileError("Invalid size for EndpointContext");
        }
    }
};
