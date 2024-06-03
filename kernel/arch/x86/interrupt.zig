//! LICENSE NOTICE
//!
//! The impletentation is heavily inspired by https://github.com/AndreaOrru/zen
//! Original LICENSE follows:
//!
//! BSD 3-Clause License
//!
//! Copyright (c) 2017, Andrea Orru
//! All rights reserved.
//!
//! Redistribution and use in source and binary forms, with or without
//! modification, are permitted provided that the following conditions are met:
//!
//! * Redistributions of source code must retain the above copyright notice, this
//!   list of conditions and the following disclaimer.
//!
//! * Redistributions in binary form must reproduce the above copyright notice,
//!   this list of conditions and the following disclaimer in the documentation
//!   and/or other materials provided with the distribution.
//!
//! * Neither the name of the copyright holder nor the names of its
//!   contributors may be used to endorse or promote products derived from
//!   this software without specific prior written permission.
//!
//! THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//! AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//! IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
//! DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
//! FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
//! DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
//! SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
//! CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
//! OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
//! OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//!

const std = @import("std");
const log = std.log.scoped(.intr);

const am = @import("asm.zig");
const gdt = @import("gdt.zig");
const idt = @import("idt.zig");
const isr = @import("isr.zig");

/// Context for interrupt handlers.
pub const Context = isr.Context;

/// Interrupt handler function signature.
pub const Handler = *const fn (*Context) void;

/// Interrupt handlers.
var handlers: [256]Handler = [_]Handler{unhandledHandler} ** 256;

/// Initialize the IDT.
pub fn init() void {
    inline for (0..num_system_exceptions) |i| {
        idt.setGate(
            i,
            .Interrupt64,
            isr.generateIsr(i),
        );
    }

    registerHandler(pageFault, unhandledFaultHandler);

    idt.init();

    asm volatile ("sti");
}

/// Notify the LAPIC that the interrupt has been handled.
pub fn notifyEoi() void {
    const eoi: *volatile u32 = @ptrFromInt(0xFEE000B0);
    eoi.* = 0;
}

/// Register interrupt handler.
pub fn registerHandler(comptime vector: u8, handler: Handler) void {
    handlers[vector] = handler;
    idt.setGate(
        vector,
        .Interrupt64,
        isr.generateIsr(vector),
    );
}

/// Called from the ISR stub.
/// Dispatches the interrupt to the appropriate handler.
pub fn dispatch(context: *Context) void {
    const vector = context.vector;
    handlers[vector](context);
}

fn unhandledHandler(context: *Context) void {
    log.err("============ Oops! ===================", .{});
    log.err("Unhandled interrupt: {s}({})", .{
        exceptionName(context.vector),
        context.vector,
    });
    log.err("Error Code: 0x{X}", .{context.error_code});
    log.err("", .{});
    log.err("RIP: 0x{X:0>16}", .{context.rip});
    log.err("RSP: 0x{X:0>16}", .{context.rsp});
    log.err("EFLAGS: 0x{X:0>16}", .{context.rflags});
    log.err("RAX: 0x{X:0>16}", .{context.registers.rax});
    log.err("RBX: 0x{X:0>16}", .{context.registers.rbx});
    log.err("RCX: 0x{X:0>16}", .{context.registers.rcx});
    log.err("RDX: 0x{X:0>16}", .{context.registers.rdx});
    log.err("RSI: 0x{X:0>16}", .{context.registers.rsi});
    log.err("RDI: 0x{X:0>16}", .{context.registers.rdi});
    log.err("RBP: 0x{X:0>16}", .{context.registers.rbp});
    log.err("R8 : 0x{X:0>16}", .{context.registers.r8});
    log.err("R9 : 0x{X:0>16}", .{context.registers.r9});
    log.err("R10: 0x{X:0>16}", .{context.registers.r10});
    log.err("R11: 0x{X:0>16}", .{context.registers.r11});
    log.err("R12: 0x{X:0>16}", .{context.registers.r12});
    log.err("R13: 0x{X:0>16}", .{context.registers.r13});
    log.err("R14: 0x{X:0>16}", .{context.registers.r14});
    log.err("R15: 0x{X:0>16}", .{context.registers.r15});
    log.err("CS: 0x{X:0>4}", .{context.cs});
    log.err("SS: 0x{X:0>4}", .{context.ss});

    asm volatile ("hlt");
}

/// TODO: move to an appropriate place
fn unhandledFaultHandler(context: *Context) void {
    log.err("============ Unhandled Fault ===================", .{});

    const cr2 = am.readCr2();
    log.err("Fault Address: 0x{X:0>16}", .{cr2});
    log.err("", .{});
    log.err("Common unhandled handler continues...", .{});
    log.err("", .{});

    unhandledHandler(context);
}

const divideByZero = 0;
const debug = 1;
const nonMaskableInterrupt = 2;
const breakpoint = 3;
const overflow = 4;
const boundRangeExceeded = 5;
const invalidOpcode = 6;
const deviceNotAvailable = 7;
const doubleFault = 8;
const coprocessorSegmentOverrun = 9;
const invalidTSS = 10;
const segmentNotPresent = 11;
const stackSegmentFault = 12;
const generalProtectionFault = 13;
const pageFault = 14;
const floatingPointException = 16;
const alignmentCheck = 17;
const machineCheck = 18;
const SIMDException = 19;
const virtualizationException = 20;
const controlProtectionExcepton = 21;

const num_system_exceptions = 32;

/// Get the name of an exception.
pub inline fn exceptionName(vector: u64) []const u8 {
    return switch (vector) {
        divideByZero => "#DE: Divide by zero",
        debug => "#DB: Debug",
        nonMaskableInterrupt => "NMI: Non-maskable interrupt",
        breakpoint => "#BP: Breakpoint",
        overflow => "#OF: Overflow",
        boundRangeExceeded => "#BR: Bound range exceeded",
        invalidOpcode => "#UD: Invalid opcode",
        deviceNotAvailable => "#NM: Device not available",
        doubleFault => "#DF: Double fault",
        coprocessorSegmentOverrun => "Coprocessor segment overrun",
        invalidTSS => "#TS: Invalid TSS",
        segmentNotPresent => "#NP: Segment not present",
        stackSegmentFault => "#SS: Stack-segment fault",
        generalProtectionFault => "#GP: General protection fault",
        pageFault => "#PF: Page fault",
        floatingPointException => "#MF: Floating-point exception",
        alignmentCheck => "#AC: Alignment check",
        machineCheck => "#MC: Machine check",
        SIMDException => "#XM: SIMD exception",
        virtualizationException => "#VE: Virtualization exception",
        controlProtectionExcepton => "#CP: Control protection exception",
        else => "Unknown exception",
    };
}
