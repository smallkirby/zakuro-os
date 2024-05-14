//! This file defines the USB SETUP Data of the USB2 and USB3 specification.

/// USB SETUP Data
pub const SetupData = packed struct(u64) {
    bm_request_type: RequestType,
    b_request: SetupDataRequest,
    w_value: u16,
    w_index: u16,
    w_length: u16,
};

const RequestType = packed struct(u8) {
    recipient: SetupDataRecipient,
    type: SetupDataType,
    dtd: SetupDataDirection,
};

const SetupDataDirection = enum(u1) {
    Out = 0,
    In = 1,
};

const SetupDataType = enum(u2) {
    Standard = 0,
    Class = 1,
    Vendor = 2,
};

const SetupDataRecipient = enum(u5) {
    Device = 0,
    Interface = 1,
    Endpoint = 2,
    Other = 3,
};

const SetupDataRequest = enum(u8) {
    GetStatus = 0,
    ClearFeature = 1,
    SetFeature = 3,
    SetAddress = 5,
    GetDescriptor = 6,
    SetDescriptor = 7,
    GetConfiguration = 8,
    SetConfiguration = 9,
    GetInterface = 10,
    SetInterface = 11,
    SynchFrame = 12,
    SetEnctyption = 13,
    GetEncryption = 14,
    SetHandshake = 15,
    GetHandshake = 16,
    SetConnection = 17,
    SetSecurityData = 18,
    GetSecurityData = 19,
    SetWusbData = 20,
    LoopbackDataWrite = 21,
    LoopbackDataRead = 22,
    SetInterfaceDs = 23,
    SetSel = 48,
    SetIsochDelay = 49,
};
