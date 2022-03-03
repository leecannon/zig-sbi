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
        return @bitCast(SpecVersion, ecall.withFidZeroArgsWithReturnNoError(.BASE, @enumToInt(BASE_FID.GET_SPEC_VERSION)));
    }

    /// Returns the current SBI implementation ID, which is different for every SBI implementation. 
    /// It is intended that this implementation ID allows software to probe for SBI implementation quirks
    pub fn getImplementationId() ImplementationId {
        return @intToEnum(ImplementationId, ecall.withFidZeroArgsWithReturnNoError(.BASE, @enumToInt(BASE_FID.GET_IMP_ID)));
    }

    /// Returns the current SBI implementation version.
    /// The encoding of this version number is specific to the SBI implementation.
    pub fn getImplementationVersion() isize {
        return ecall.withFidZeroArgsWithReturnNoError(.BASE, @enumToInt(BASE_FID.GET_IMP_VERSION));
    }

    /// Returns false if the given SBI extension ID (EID) is not available, or true if it is available.
    pub fn probeExtension(eid: EID) bool {
        return ecall.withFidOneArgsWithReturnNoError(.BASE, @enumToInt(BASE_FID.PROBE_EXT), @enumToInt(eid)) != 0;
    }

    /// Return a value that is legal for the `mvendorid` CSR and 0 is always a legal value for this CSR.
    pub fn machineVendorId() isize {
        return ecall.withFidZeroArgsWithReturnNoError(.BASE, @enumToInt(BASE_FID.GET_MVENDORID));
    }

    /// Return a value that is legal for the `marchid` CSR and 0 is always a legal value for this CSR.
    pub fn machineArchId() isize {
        return ecall.withFidZeroArgsWithReturnNoError(.BASE, @enumToInt(BASE_FID.GET_MARCHID));
    }

    /// Return a value that is legal for the `mimpid` CSR and 0 is always a legal value for this CSR.
    pub fn machineImplementationId() isize {
        return ecall.withFidZeroArgsWithReturnNoError(.BASE, @enumToInt(BASE_FID.GET_MIMPID));
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

const ecall = struct {
    inline fn withFidZeroArgsWithReturnNoError(eid: EID, fid: i32) isize {
        return asm volatile ("ecall"
            : [value] "={x11}" (-> isize),
            : [eid] "{x17}" (@enumToInt(eid)),
              [fid] "{x16}" (fid),
            : "memory", "x10"
        );
    }

    inline fn withFidOneArgsWithReturnNoError(eid: EID, fid: i32, a0: isize) isize {
        return asm volatile ("ecall"
            : [value] "={x11}" (-> isize),
            : [eid] "{x17}" (@enumToInt(eid)),
              [fid] "{x16}" (fid),
              [arg0] "{x10}" (a0),
            : "memory", "x10"
        );
    }

    inline fn withFidThreeArgsWithReturnWithError(eid: EID, fid: i32, a0: isize, a1: isize, a2: isize) Error!isize {
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
        return err.toError(Error);
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
        const errors: []std.builtin.TypeInfo.Error = @typeInfo(ErrorT).ErrorSet.?;
        inline for (errors) |err| {
            if (self == @field(ErrorCode, err.name)) return @field(Error, err.name);
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
