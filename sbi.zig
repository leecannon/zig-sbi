const std = @import("std");
const builtin = @import("builtin");

const is_64: bool = switch (builtin.cpu.arch) {
    .riscv64 => true,
    .riscv32 => false,
    else => |arch| @compileError("only riscv64 and riscv32 targets supported, found target: " ++ @tagName(arch)),
};

pub const Error = error{
    FAILED,
    NOT_SUPPORTED,
    INVALID_PARAM,
    DENIED,
    INVALID_ADDRESS,
    ALREADY_AVAILABLE,
    ALREADY_STARTED,
    ALREADY_STOPPED,
};

pub const EID = enum(i32) {
    LEGACY_SET_TIMER = 0x0,
    LEGACY_CONSOLE_PUTCHAR = 0x1,
    LEGACY_CONSOLE_GETCHAR = 0x2,
    LEGACY_CLEAR_IPI = 0x3,
    LEGACY_SEND_IPI = 0x4,
    LEGACY_REMOTE_FENCE_I = 0x5,
    LEGACY_REMOTE_SFENCE_VMA = 0x6,
    LEGACY_REMOTE_SFENCE_VMA_ASID = 0x7,
    LEGACY_SHUTDOWN = 0x8,
    BASE = 0x10,
    TIME = 0x54494D45,
    IPI = 0x735049,
    RFENCE = 0x52464E43,
    HSM = 0x48534D,
    SRST = 0x53525354,
    PMU = 0x504D55,

    _,
};

/// The base extension is designed to be as small as possible. 
/// As such, it only contains functionality for probing which SBI extensions are available and
/// for querying the version of the SBI. 
/// All functions in the base extension must be supported by all SBI implementations, so there
/// are no error returns defined.
pub const base = struct {
    /// Returns the current SBI specification version.
    pub fn getSpecVersion() SpecVersion {
        return @bitCast(SpecVersion, ecall.zeroArgsWithReturnNoError(.BASE, @enumToInt(BASE_FID.GET_SPEC_VERSION)));
    }

    /// Returns the current SBI implementation ID, which is different for every SBI implementation. 
    /// It is intended that this implementation ID allows software to probe for SBI implementation quirks
    pub fn getImplementationId() ImplementationId {
        return @intToEnum(ImplementationId, ecall.zeroArgsWithReturnNoError(.BASE, @enumToInt(BASE_FID.GET_IMP_ID)));
    }

    /// Returns the current SBI implementation version.
    /// The encoding of this version number is specific to the SBI implementation.
    pub fn getImplementationVersion() isize {
        return ecall.zeroArgsWithReturnNoError(.BASE, @enumToInt(BASE_FID.GET_IMP_VERSION));
    }

    /// Returns false if the given SBI extension ID (EID) is not available, or true if it is available.
    pub fn probeExtension(eid: EID) bool {
        return ecall.oneArgsWithReturnNoError(.BASE, @enumToInt(BASE_FID.PROBE_EXT), @enumToInt(eid)) != 0;
    }

    /// Return a value that is legal for the `mvendorid` CSR and 0 is always a legal value for this CSR.
    pub fn machineVendorId() isize {
        return ecall.zeroArgsWithReturnNoError(.BASE, @enumToInt(BASE_FID.GET_MVENDORID));
    }

    /// Return a value that is legal for the `marchid` CSR and 0 is always a legal value for this CSR.
    pub fn machineArchId() isize {
        return ecall.zeroArgsWithReturnNoError(.BASE, @enumToInt(BASE_FID.GET_MARCHID));
    }

    /// Return a value that is legal for the `mimpid` CSR and 0 is always a legal value for this CSR.
    pub fn machineImplementationId() isize {
        return ecall.zeroArgsWithReturnNoError(.BASE, @enumToInt(BASE_FID.GET_MIMPID));
    }

    pub const ImplementationId = enum(isize) {
        @"Berkeley Boot Loader (BBL)" = 0,
        OpenSBI = 1,
        Xvisor = 2,
        KVM = 3,
        RustSBI = 4,
        Diosix = 5,
        Coffer = 6,
        _,
    };

    pub const SpecVersion = packed struct {
        minor: u24,
        major: u7,
        _reserved: u1,
        _: if (is_64) u32 else u0,

        test {
            try std.testing.expectEqual(@sizeOf(usize), @sizeOf(SpecVersion));
            try std.testing.expectEqual(@bitSizeOf(usize), @bitSizeOf(SpecVersion));
        }

        comptime {
            std.testing.refAllDecls(@This());
        }
    };

    const BASE_FID = enum(i32) {
        GET_SPEC_VERSION = 0x0,
        GET_IMP_ID = 0x1,
        GET_IMP_VERSION = 0x2,
        PROBE_EXT = 0x3,
        GET_MVENDORID = 0x4,
        GET_MARCHID = 0x5,
        GET_MIMPID = 0x6,
    };

    comptime {
        std.testing.refAllDecls(@This());
    }
};

/// These legacy SBI extension are deprecated in favor of the other extensions.
/// Each function needs to be individually probed to check for support.
pub const legacy = struct {
    pub fn setTimerAvailable() bool {
        return base.probeExtension(.LEGACY_SET_TIMER);
    }

    /// Programs the clock for next event after time_value time.
    /// This function also clears the pending timer interrupt bit.
    ///
    /// If the supervisor wishes to clear the timer interrupt without scheduling the next timer event,
    /// it can either request a timer interrupt infinitely far into the future
    /// (i.e., `@bitCast(u64, @as(i64, -1))`), or it can instead mask the timer interrupt by clearing `sie.STIE` CSR bit.
    pub fn setTimer(time_value: u64) void {
        return ecall.legacyOneArgs64NoReturnWithError(.LEGACY_SET_TIMER, time_value, error{NOT_SUPPORTED}) catch unreachable;
    }

    pub fn consolePutCharAvailable() bool {
        return base.probeExtension(.LEGACY_CONSOLE_PUTCHAR);
    }

    /// Write data present in char to debug console.
    /// Unlike `consoleGetChar`, this SBI call will block if there remain any pending characters to be
    /// transmitted or if the receiving terminal is not yet ready to receive the byte.
    /// However, if the console doesn’t exist at all, then the character is thrown away
    pub fn consolePutChar(char: u8) void {
        return ecall.legacyOneArgsNoReturnWithError(.LEGACY_CONSOLE_PUTCHAR, char, error{NOT_SUPPORTED}) catch unreachable;
    }

    pub fn consoleGetCharAvailable() bool {
        return base.probeExtension(.LEGACY_CONSOLE_GETCHAR);
    }

    /// Read a byte from debug console.
    pub fn consoleGetChar() error{FAILED}!u8 {
        return @intCast(
            u8,
            ecall.legacyZeroArgsWithReturnWithError(.LEGACY_CONSOLE_GETCHAR, error{ NOT_SUPPORTED, FAILED }) catch |err| switch (err) {
                error.NOT_SUPPORTED => unreachable,
                else => |e| return e,
            },
        );
    }

    pub fn clearIPIAvailable() bool {
        return base.probeExtension(.LEGACY_CLEAR_IPI);
    }

    /// Clears the pending IPIs if any. The IPI is cleared only in the hart for which this SBI call is invoked.
    /// `clearIPI` is deprecated because S-mode code can clear `sip.SSIP` CSR bit directly
    pub fn clearIPI() void {
        ecall.legacyZeroArgsNoReturnWithError(.LEGACY_CLEAR_IPI, error{NOT_SUPPORTED}) catch unreachable;
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

const ecall = struct {
    inline fn zeroArgsWithReturnNoError(eid: EID, fid: i32) isize {
        return asm volatile ("ecall"
            : [value] "={x11}" (-> isize),
            : [eid] "{x17}" (@enumToInt(eid)),
              [fid] "{x16}" (fid),
            : "memory", "x10"
        );
    }

    inline fn oneArgsWithReturnNoError(eid: EID, fid: i32, a0: isize) isize {
        return asm volatile ("ecall"
            : [value] "={x11}" (-> isize),
            : [eid] "{x17}" (@enumToInt(eid)),
              [fid] "{x16}" (fid),
              [arg0] "{x10}" (a0),
            : "memory", "x10"
        );
    }

    inline fn legacyOneArgs64NoReturnWithError(eid: EID, a0: u64, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;
        if (is_64) {
            asm volatile ("ecall"
                : [err] "={x10}" (err),
                : [eid] "{x17}" (@enumToInt(eid)),
                  [arg0] "{x10}" (a0),
                : "memory"
            );
        } else {
            asm volatile ("ecall"
                : [err] "={x10}" (err),
                : [eid] "{x17}" (@enumToInt(eid)),
                  [arg0_lo] "{x10}" (@truncate(u32, a0)),
                  [arg0_hi] "{x11}" (@truncate(u32, a0 >> 32)),
                : "memory"
            );
        }

        if (err == .SUCCESS) return;
        return err.toError(ErrorT);
    }

    inline fn legacyOneArgsNoReturnWithError(eid: EID, a0: isize, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;
        asm volatile ("ecall"
            : [err] "={x10}" (err),
            : [eid] "{x17}" (@enumToInt(eid)),
              [arg0] "{x10}" (a0),
            : "memory"
        );

        if (err == .SUCCESS) return;
        return err.toError(ErrorT);
    }

    inline fn legacyZeroArgsWithReturnWithError(eid: EID, comptime ErrorT: type) ErrorT!isize {
        var val: isize = undefined;
        asm volatile ("ecall"
            : [val] "={x10}" (val),
            : [eid] "{x17}" (@enumToInt(eid)),
            : "memory"
        );
        if (val >= 0) return val;
        return @intToEnum(ErrorCode, val).toError(ErrorT);
    }

    inline fn legacyZeroArgsNoReturnWithError(eid: EID, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;
        asm volatile ("ecall"
            : [err] "={x10}" (err),
            : [eid] "{x17}" (@enumToInt(eid)),
            : "memory"
        );
        if (err == .SUCCESS) return;
        return err.toError(ErrorT);
    }

    inline fn threeArgsWithReturnWithError(eid: EID, fid: i32, a0: isize, a1: isize, a2: isize, comptime ErrorT: type) ErrorT!isize {
        var err: ErrorCode = undefined;
        var value: isize = undefined;
        asm volatile ("ecall"
            : [err] "={x10}" (err),
              [value] "={x11}" (value),
            : [eid] "{x17}" (@enumToInt(eid)),
              [fid] "{x16}" (fid),
              [arg0] "{x10}" (a0),
              [arg1] "{x11}" (a1),
              [arg2] "{x12}" (a2),
            : "memory"
        );
        if (err == .SUCCESS) return value;
        return err.toError(ErrorT);
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

const ErrorCode = enum(isize) {
    SUCCESS = 0,
    FAILED = -1,
    NOT_SUPPORTED = -2,
    INVALID_PARAM = -3,
    DENIED = -4,
    INVALID_ADDRESS = -5,
    ALREADY_AVAILABLE = -6,
    ALREADY_STARTED = -7,
    ALREADY_STOPPED = -8,

    fn toError(self: ErrorCode, comptime ErrorT: type) ErrorT {
        const errors: []const std.builtin.TypeInfo.Error = @typeInfo(ErrorT).ErrorSet.?;
        inline for (errors) |err| {
            if (self == @field(ErrorCode, err.name)) return @field(ErrorT, err.name);
        }
        unreachable;
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

comptime {
    std.testing.refAllDecls(@This());
}
