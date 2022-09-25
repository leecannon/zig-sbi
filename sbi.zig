const std = @import("std");
const builtin = @import("builtin");

const runtime_safety = std.debug.runtime_safety;

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

        comptime {
            std.debug.assert(@sizeOf(usize) == @sizeOf(SpecVersion));
            std.debug.assert(@bitSizeOf(usize) == @bitSizeOf(SpecVersion));
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
    ///
    /// This function returns `ImplementationDefinedError` as an implementation specific error is possible.
    pub fn setTimer(time_value: u64) ImplementationDefinedError {
        return ecall.legacyOneArgs64NoReturnWithRawError(.LEGACY_SET_TIMER, time_value);
    }

    pub fn consolePutCharAvailable() bool {
        return base.probeExtension(.LEGACY_CONSOLE_PUTCHAR);
    }

    /// Write data present in char to debug console.
    /// Unlike `consoleGetChar`, this SBI call will block if there remain any pending characters to be
    /// transmitted or if the receiving terminal is not yet ready to receive the byte.
    /// However, if the console doesn’t exist at all, then the character is thrown away
    ///
    /// This function returns `ImplementationDefinedError` as an implementation specific error is possible.
    pub fn consolePutChar(char: u8) ImplementationDefinedError {
        return ecall.legacyOneArgsNoReturnWithRawError(.LEGACY_CONSOLE_PUTCHAR, char);
    }

    pub fn consoleGetCharAvailable() bool {
        return base.probeExtension(.LEGACY_CONSOLE_GETCHAR);
    }

    /// Read a byte from debug console.
    pub fn consoleGetChar() error{FAILED}!u8 {
        if (runtime_safety) {
            return @intCast(
                u8,
                ecall.legacyZeroArgsWithReturnWithError(
                    .LEGACY_CONSOLE_GETCHAR,
                    error{ NOT_SUPPORTED, FAILED },
                ) catch |err| switch (err) {
                    error.NOT_SUPPORTED => unreachable,
                    else => |e| return e,
                },
            );
        }

        return @intCast(
            u8,
            try ecall.legacyZeroArgsWithReturnWithError(.LEGACY_CONSOLE_GETCHAR, error{FAILED}),
        );
    }

    pub fn clearIPIAvailable() bool {
        return base.probeExtension(.LEGACY_CLEAR_IPI);
    }

    /// Clears the pending IPIs if any. The IPI is cleared only in the hart for which this SBI call is invoked.
    /// `clearIPI` is deprecated because S-mode code can clear `sip.SSIP` CSR bit directly
    pub fn clearIPI() void {
        if (runtime_safety) {
            ecall.legacyZeroArgsNoReturnWithError(.LEGACY_CLEAR_IPI, error{NOT_SUPPORTED}) catch unreachable;
            return;
        }

        ecall.legacyZeroArgsNoReturnNoError(.LEGACY_CLEAR_IPI);
    }

    pub fn sendIPIAvailable() bool {
        return base.probeExtension(.LEGACY_SEND_IPI);
    }

    /// Send an inter-processor interrupt to all the harts defined in hart_mask.
    /// Interprocessor interrupts manifest at the receiving harts as Supervisor Software Interrupts.
    /// `hart_mask` is a virtual address that points to a bit-vector of harts. The bit vector is represented as a
    /// sequence of `usize` whose length equals the number of harts in the system divided by the number of bits in a `usize`,
    /// rounded up to the next integer.
    ///
    /// This function returns `ImplementationDefinedError` as an implementation specific error is possible.
    pub fn sendIPI(hart_mask: [*]const usize) ImplementationDefinedError {
        return ecall.legacyOneArgsNoReturnWithRawError(.LEGACY_SEND_IPI, @bitCast(isize, @ptrToInt(hart_mask)));
    }

    pub fn remoteFenceIAvailable() bool {
        return base.probeExtension(.LEGACY_REMOTE_FENCE_I);
    }

    /// Instructs remote harts to execute FENCE.I instruction.
    /// The `hart_mask` is the same as described in `sendIPI`.
    ///
    /// This function returns `ImplementationDefinedError` as an implementation specific error is possible.
    pub fn remoteFenceI(hart_mask: [*]const usize) ImplementationDefinedError {
        return ecall.legacyOneArgsNoReturnWithRawError(.LEGACY_REMOTE_FENCE_I, @bitCast(isize, @ptrToInt(hart_mask)));
    }

    pub fn remoteSFenceVMAAvailable() bool {
        return base.probeExtension(.LEGACY_REMOTE_SFENCE_VMA);
    }

    /// Instructs the remote harts to execute one or more SFENCE.VMA instructions, covering the range of
    /// virtual addresses between `start` and `size`.
    /// The `hart_mask` is the same as described in `sendIPI`.
    pub fn remoteSFenceVMA(hart_mask: [*]const usize, start: usize, size: usize) void {
        if (runtime_safety) {
            ecall.legacyThreeArgsNoReturnWithError(
                .LEGACY_REMOTE_SFENCE_VMA,
                @bitCast(isize, @ptrToInt(hart_mask)),
                @bitCast(isize, start),
                @bitCast(isize, size),
                error{NOT_SUPPORTED},
            ) catch unreachable;
            return;
        }

        ecall.legacyThreeArgsNoReturnNoError(
            .LEGACY_REMOTE_SFENCE_VMA,
            @bitCast(isize, @ptrToInt(hart_mask)),
            @bitCast(isize, start),
            @bitCast(isize, size),
        );
    }

    pub fn remoteSFenceVMAWithASIDAvailable() bool {
        return base.probeExtension(.LEGACY_REMOTE_SFENCE_VMA_ASID);
    }

    /// Instruct the remote harts to execute one or more SFENCE.VMA instructions, covering the range of
    /// virtual addresses between `start` and `size`. This covers only the given ASID.
    /// The `hart_mask` is the same as described in `sendIPI`.
    ///
    /// This function returns `ImplementationDefinedError` as an implementation specific error is possible.
    pub fn remoteSFenceVMAWithASID(hart_mask: [*]const usize, start: usize, size: usize, asid: usize) ImplementationDefinedError {
        return ecall.legacyFourArgsNoReturnWithRawError(
            .LEGACY_REMOTE_SFENCE_VMA_ASID,
            @bitCast(isize, @ptrToInt(hart_mask)),
            @bitCast(isize, start),
            @bitCast(isize, size),
            @bitCast(isize, asid),
        );
    }

    pub fn systemShutdownAvailable() bool {
        return base.probeExtension(.LEGACY_SHUTDOWN);
    }

    /// Puts all the harts to shutdown state from supervisor point of view.
    ///
    /// This SBI call doesn't return irrespective whether it succeeds or fails.
    pub fn systemShutdown() void {
        if (runtime_safety) {
            ecall.legacyZeroArgsNoReturnWithError(.LEGACY_SHUTDOWN, error{NOT_SUPPORTED}) catch unreachable;
        } else {
            ecall.legacyZeroArgsNoReturnNoError(.LEGACY_SHUTDOWN);
        }
        unreachable;
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

pub const time = struct {
    pub fn available() bool {
        return base.probeExtension(.TIME);
    }

    /// Programs the clock for next event after time_value time.
    /// This function also clears the pending timer interrupt bit.
    ///
    /// If the supervisor wishes to clear the timer interrupt without scheduling the next timer event,
    /// it can either request a timer interrupt infinitely far into the future
    /// (i.e., `@bitCast(u64, @as(i64, -1))`), or it can instead mask the timer interrupt by clearing `sie.STIE` CSR bit.
    pub fn setTimer(time_value: u64) void {
        if (runtime_safety) {
            ecall.oneArgs64NoReturnWithError(
                .TIME,
                @enumToInt(TIME_FID.TIME_SET_TIMER),
                time_value,
                error{NOT_SUPPORTED},
            ) catch unreachable;
            return;
        }

        ecall.oneArgs64NoReturnNoError(
            .TIME,
            @enumToInt(TIME_FID.TIME_SET_TIMER),
            time_value,
        );
    }

    const TIME_FID = enum(i32) {
        TIME_SET_TIMER = 0x0,
    };

    comptime {
        std.testing.refAllDecls(@This());
    }
};

pub const HartMask = union(enum) {
    /// all available ids must be considered
    all,
    mask: struct {
        /// a scalar bit-vector containing ids
        mask: usize,
        /// the starting id from which bit-vector must be computed
        base: usize,
    },
};

pub const ipi = struct {
    pub fn available() bool {
        return base.probeExtension(.IPI);
    }

    /// Send an inter-processor interrupt to all the harts defined in `hart_mask`.
    /// Interprocessor interrupts manifest at the receiving harts as the supervisor software interrupts.
    pub fn sendIPI(hart_mask: HartMask) error{INVALID_PARAM}!void {
        var bit_mask: isize = undefined;
        var mask_base: isize = undefined;

        switch (hart_mask) {
            .all => {
                bit_mask = 0;
                mask_base = 0;
            },
            .mask => |mask| {
                bit_mask = @bitCast(isize, mask.mask);
                mask_base = @bitCast(isize, mask.base);
            },
        }

        if (runtime_safety) {
            ecall.twoArgsNoReturnWithError(
                .IPI,
                @enumToInt(IPI_FID.SEND_IPI),
                bit_mask,
                mask_base,
                error{ NOT_SUPPORTED, INVALID_PARAM },
            ) catch |err| switch (err) {
                error.NOT_SUPPORTED => unreachable,
                else => |e| return e,
            };

            return;
        }

        return ecall.twoArgsNoReturnWithError(
            .IPI,
            @enumToInt(IPI_FID.SEND_IPI),
            bit_mask,
            mask_base,
            error{INVALID_PARAM},
        );
    }

    const IPI_FID = enum(i32) {
        SEND_IPI = 0x0,
    };

    comptime {
        std.testing.refAllDecls(@This());
    }
};

/// Any function that wishes to use range of addresses (i.e. `start_addr` and `size`), have to abide by the below
/// constraints on range parameters.
///
/// The remote fence function acts as a full TLB flush if
///   • `start_addr` and `size` are both 0
///   • `size` is equal to 2^XLEN-1
pub const rfence = struct {
    pub fn available() bool {
        return base.probeExtension(.RFENCE);
    }

    /// Instructs remote harts to execute FENCE.I instruction.
    pub fn remoteFenceI(hart_mask: HartMask) error{INVALID_PARAM}!void {
        var bit_mask: isize = undefined;
        var mask_base: isize = undefined;

        switch (hart_mask) {
            .all => {
                bit_mask = 0;
                mask_base = 0;
            },
            .mask => |mask| {
                bit_mask = @bitCast(isize, mask.mask);
                mask_base = @bitCast(isize, mask.base);
            },
        }

        if (runtime_safety) {
            ecall.twoArgsNoReturnWithError(
                .RFENCE,
                @enumToInt(RFENCE_FID.FENCE_I),
                bit_mask,
                mask_base,
                error{ NOT_SUPPORTED, INVALID_PARAM },
            ) catch |err| switch (err) {
                error.NOT_SUPPORTED => unreachable,
                else => |e| return e,
            };

            return;
        }

        return ecall.twoArgsNoReturnWithError(
            .RFENCE,
            @enumToInt(RFENCE_FID.FENCE_I),
            bit_mask,
            mask_base,
            error{INVALID_PARAM},
        );
    }

    /// Instructs the remote harts to execute one or more SFENCE.VMA instructions, covering the range of
    /// virtual addresses between `start_addr` and `size`.
    pub fn remoteSFenceVMA(
        hart_mask: HartMask,
        start_addr: usize,
        size: usize,
    ) error{ INVALID_PARAM, INVALID_ADDRESS }!void {
        var bit_mask: isize = undefined;
        var mask_base: isize = undefined;

        switch (hart_mask) {
            .all => {
                bit_mask = 0;
                mask_base = 0;
            },
            .mask => |mask| {
                bit_mask = @bitCast(isize, mask.mask);
                mask_base = @bitCast(isize, mask.base);
            },
        }

        if (runtime_safety) {
            ecall.fourArgsNoReturnWithError(
                .RFENCE,
                @enumToInt(RFENCE_FID.SFENCE_VMA),
                bit_mask,
                mask_base,
                @bitCast(isize, start_addr),
                @bitCast(isize, size),
                error{ NOT_SUPPORTED, INVALID_PARAM, INVALID_ADDRESS },
            ) catch |err| switch (err) {
                error.NOT_SUPPORTED => unreachable,
                else => |e| return e,
            };

            return;
        }

        return ecall.fourArgsNoReturnWithError(
            .RFENCE,
            @enumToInt(RFENCE_FID.SFENCE_VMA),
            bit_mask,
            mask_base,
            @bitCast(isize, start_addr),
            @bitCast(isize, size),
            error{ INVALID_PARAM, INVALID_ADDRESS },
        );
    }

    /// Instructs the remote harts to execute one or more SFENCE.VMA instructions, covering the range of
    /// virtual addresses between `start_addr` and `size`.
    /// This covers only the given ASID.
    pub fn remoteSFenceVMAWithASID(
        hart_mask: HartMask,
        start_addr: usize,
        size: usize,
        asid: usize,
    ) error{ INVALID_PARAM, INVALID_ADDRESS }!void {
        var bit_mask: isize = undefined;
        var mask_base: isize = undefined;

        switch (hart_mask) {
            .all => {
                bit_mask = 0;
                mask_base = 0;
            },
            .mask => |mask| {
                bit_mask = @bitCast(isize, mask.mask);
                mask_base = @bitCast(isize, mask.base);
            },
        }

        if (runtime_safety) {
            ecall.fiveArgsNoReturnWithError(
                .RFENCE,
                @enumToInt(RFENCE_FID.SFENCE_VMA_ASID),
                bit_mask,
                mask_base,
                @bitCast(isize, start_addr),
                @bitCast(isize, size),
                @bitCast(isize, asid),
                error{ NOT_SUPPORTED, INVALID_PARAM, INVALID_ADDRESS },
            ) catch |err| switch (err) {
                error.NOT_SUPPORTED => unreachable,
                else => |e| return e,
            };

            return;
        }

        return ecall.fiveArgsNoReturnWithError(
            .RFENCE,
            @enumToInt(RFENCE_FID.SFENCE_VMA_ASID),
            bit_mask,
            mask_base,
            @bitCast(isize, start_addr),
            @bitCast(isize, size),
            @bitCast(isize, asid),
            error{ INVALID_PARAM, INVALID_ADDRESS },
        );
    }

    /// Instruct the remote harts to execute one or more HFENCE.GVMA instructions, covering the range of
    /// guest physical addresses between start and size only for the given VMID.
    /// This function call is only valid for harts implementing hypervisor extension.
    pub fn remoteHFenceGVMAWithVMID(
        hart_mask: HartMask,
        start_addr: usize,
        size: usize,
        vmid: usize,
    ) error{ NOT_SUPPORTED, INVALID_PARAM, INVALID_ADDRESS }!void {
        var bit_mask: isize = undefined;
        var mask_base: isize = undefined;

        switch (hart_mask) {
            .all => {
                bit_mask = 0;
                mask_base = 0;
            },
            .mask => |mask| {
                bit_mask = @bitCast(isize, mask.mask);
                mask_base = @bitCast(isize, mask.base);
            },
        }

        return ecall.fiveArgsNoReturnWithError(
            .RFENCE,
            @enumToInt(RFENCE_FID.HFENCE_GVMA_VMID),
            bit_mask,
            mask_base,
            @bitCast(isize, start_addr),
            @bitCast(isize, size),
            @bitCast(isize, vmid),
            error{ NOT_SUPPORTED, INVALID_PARAM, INVALID_ADDRESS },
        );
    }

    /// Instruct the remote harts to execute one or more HFENCE.GVMA instructions, covering the range of
    /// guest physical addresses between start and size only for all guests.
    /// This function call is only valid for harts implementing hypervisor extension.
    pub fn remoteHFenceGVMA(
        hart_mask: HartMask,
        start_addr: usize,
        size: usize,
    ) error{ NOT_SUPPORTED, INVALID_PARAM, INVALID_ADDRESS }!void {
        var bit_mask: isize = undefined;
        var mask_base: isize = undefined;

        switch (hart_mask) {
            .all => {
                bit_mask = 0;
                mask_base = 0;
            },
            .mask => |mask| {
                bit_mask = @bitCast(isize, mask.mask);
                mask_base = @bitCast(isize, mask.base);
            },
        }

        return ecall.fourArgsNoReturnWithError(
            .RFENCE,
            @enumToInt(RFENCE_FID.HFENCE_GVMA),
            bit_mask,
            mask_base,
            @bitCast(isize, start_addr),
            @bitCast(isize, size),
            error{ NOT_SUPPORTED, INVALID_PARAM, INVALID_ADDRESS },
        );
    }

    /// Instruct the remote harts to execute one or more HFENCE.VVMA instructions, covering the range of
    /// guest virtual addresses between `start_addr` and `size` for the given ASID and current VMID (in hgatp CSR) of
    /// calling hart.
    /// This function call is only valid for harts implementing hypervisor extension.
    pub fn remoteHFenceVVMAWithASID(
        hart_mask: HartMask,
        start_addr: usize,
        size: usize,
        asid: usize,
    ) error{ NOT_SUPPORTED, INVALID_PARAM, INVALID_ADDRESS }!void {
        var bit_mask: isize = undefined;
        var mask_base: isize = undefined;

        switch (hart_mask) {
            .all => {
                bit_mask = 0;
                mask_base = 0;
            },
            .mask => |mask| {
                bit_mask = @bitCast(isize, mask.mask);
                mask_base = @bitCast(isize, mask.base);
            },
        }

        return ecall.fiveArgsNoReturnWithError(
            .RFENCE,
            @enumToInt(RFENCE_FID.HFENCE_VVMA_ASID),
            bit_mask,
            mask_base,
            @bitCast(isize, start_addr),
            @bitCast(isize, size),
            @bitCast(isize, asid),
            error{ NOT_SUPPORTED, INVALID_PARAM, INVALID_ADDRESS },
        );
    }

    /// Instruct the remote harts to execute one or more HFENCE.VVMA instructions, covering the range of
    /// guest virtual addresses between `start_addr` and `size` for current VMID (in hgatp CSR) of calling hart.
    /// This function call is only valid for harts implementing hypervisor extension.
    pub fn remoteHFenceVVMA(
        hart_mask: HartMask,
        start_addr: usize,
        size: usize,
    ) error{ NOT_SUPPORTED, INVALID_PARAM, INVALID_ADDRESS }!void {
        var bit_mask: isize = undefined;
        var mask_base: isize = undefined;

        switch (hart_mask) {
            .all => {
                bit_mask = 0;
                mask_base = 0;
            },
            .mask => |mask| {
                bit_mask = @bitCast(isize, mask.mask);
                mask_base = @bitCast(isize, mask.base);
            },
        }

        return ecall.fourArgsNoReturnWithError(
            .RFENCE,
            @enumToInt(RFENCE_FID.HFENCE_VVMA),
            bit_mask,
            mask_base,
            @bitCast(isize, start_addr),
            @bitCast(isize, size),
            error{ NOT_SUPPORTED, INVALID_PARAM, INVALID_ADDRESS },
        );
    }

    const RFENCE_FID = enum(i32) {
        FENCE_I = 0x0,
        SFENCE_VMA = 0x1,
        SFENCE_VMA_ASID = 0x2,
        HFENCE_GVMA_VMID = 0x3,
        HFENCE_GVMA = 0x4,
        HFENCE_VVMA_ASID = 0x5,
        HFENCE_VVMA = 0x6,
    };

    comptime {
        std.testing.refAllDecls(@This());
    }
};

/// The Hart State Management (HSM) Extension introduces a set of hart states and a set of functions
/// which allow the supervisor-mode software to request a hart state change.
pub const hsm = struct {
    pub fn available() bool {
        return base.probeExtension(.HSM);
    }

    /// Request the SBI implementation to start executing the target hart in supervisor-mode at address specified
    /// by `start_addr` parameter with specific registers values described in the SBI Specification.
    ///
    /// This call is asynchronous — more specifically, `hartStart` may return before the target hart starts executing
    /// as long as the SBI implementation is capable of ensuring the return code is accurate.
    ///
    /// If the SBI implementation is a platform runtime firmware executing in machine-mode (M-mode) then it MUST
    /// configure PMP and other M-mode state before transferring control to supervisor-mode software.
    ///
    /// The `hartid` parameter specifies the target hart which is to be started.
    ///
    /// The `start_addr` parameter points to a runtime-specified physical address, where the hart can start
    /// executing in supervisor-mode.
    ///
    /// The `value` parameter is a XLEN-bit value which will be set in the a1 register when the hart starts
    /// executing at `start_addr`.
    pub fn hartStart(
        hartid: usize,
        start_addr: usize,
        value: usize,
    ) error{ INVALID_ADDRESS, INVALID_PARAM, ALREADY_AVAILABLE, FAILED }!void {
        if (runtime_safety) {
            ecall.threeArgsNoReturnWithError(
                .HSM,
                @enumToInt(HSM_FID.HART_START),
                @bitCast(isize, hartid),
                @bitCast(isize, start_addr),
                @bitCast(isize, value),
                error{ NOT_SUPPORTED, INVALID_ADDRESS, INVALID_PARAM, ALREADY_AVAILABLE, FAILED },
            ) catch |err| switch (err) {
                error.NOT_SUPPORTED => unreachable,
                else => |e| return e,
            };
            return;
        }

        return ecall.threeArgsNoReturnWithError(
            .HSM,
            @enumToInt(HSM_FID.HART_START),
            @bitCast(isize, hartid),
            @bitCast(isize, start_addr),
            @bitCast(isize, value),
            error{ INVALID_ADDRESS, INVALID_PARAM, ALREADY_AVAILABLE, FAILED },
        );
    }

    /// Request the SBI implementation to stop executing the calling hart in supervisor-mode and return it’s
    /// ownership to the SBI implementation.
    /// This call is not expected to return under normal conditions.
    /// `hartStop` must be called with the supervisor-mode interrupts disabled.
    pub fn hartStop() error{FAILED}!void {
        if (runtime_safety) {
            ecall.zeroArgsNoReturnWithError(
                .HSM,
                @enumToInt(HSM_FID.HART_STOP),
                error{ NOT_SUPPORTED, FAILED },
            ) catch |err| switch (err) {
                error.NOT_SUPPORTED => unreachable,
                else => |e| return e,
            };
        } else {
            try ecall.zeroArgsNoReturnWithError(
                .HSM,
                @enumToInt(HSM_FID.HART_STOP),
                error{FAILED},
            );
        }
        unreachable;
    }

    /// Get the current status (or HSM state id) of the given hart
    ///
    /// The harts may transition HSM states at any time due to any concurrent `hartStart`, `hartStop` or `hartSuspend` calls,
    /// the return value from this function may not represent the actual state of the hart at the time of return value verification.
    pub fn hartStatus(hartid: usize) error{INVALID_PARAM}!State {
        if (runtime_safety) {
            return @intToEnum(State, ecall.oneArgsWithReturnWithError(
                .HSM,
                @enumToInt(HSM_FID.HART_GET_STATUS),
                @bitCast(isize, hartid),
                error{ NOT_SUPPORTED, INVALID_PARAM },
            ) catch |err| switch (err) {
                error.NOT_SUPPORTED => unreachable,
                else => |e| return e,
            });
        }

        return @intToEnum(State, try ecall.oneArgsWithReturnWithError(
            .HSM,
            @enumToInt(HSM_FID.HART_GET_STATUS),
            @bitCast(isize, hartid),
            error{INVALID_PARAM},
        ));
    }

    /// Request the SBI implementation to put the calling hart in a platform specific suspend (or low power)
    /// state specified by the `suspend_type` parameter.
    ///
    /// The hart will automatically come out of suspended state and resume normal execution when it receives an interrupt
    /// or platform specific hardware event.
    ///
    /// The platform specific suspend states for a hart can be either retentive or non-retentive in nature. A retentive
    /// suspend state will preserve hart register and CSR values for all privilege modes whereas a non-retentive suspend
    /// state will not preserve hart register and CSR values.
    ///
    /// Resuming from a retentive suspend state is straight forward and the supervisor-mode software will see
    /// SBI suspend call return without any failures.
    ///
    /// The `resume_addr` parameter is unused during retentive suspend.
    ///
    /// Resuming from a non-retentive suspend state is relatively more involved and requires software to restore various
    /// hart registers and CSRs for all privilege modes. Upon resuming from non-retentive suspend state, the hart will
    /// jump to supervisor-mode at address specified by `resume_addr` with specific registers values described
    /// in the SBI Specification
    ///
    /// The `resume_addr` parameter points to a runtime-specified physical address, where the hart can resume execution in
    /// supervisor-mode after a non-retentive suspend.
    ///
    /// The `value` parameter is a XLEN-bit value which will be set in the a1 register when the hart resumes execution at
    /// `resume_addr` after a non-retentive suspend.
    pub fn hartSuspend(
        suspend_type: SuspendType,
        resume_addr: usize,
        value: usize,
    ) error{ NOT_SUPPORTED, INVALID_PARAM, INVALID_ADDRESS, FAILED }!void {
        return ecall.threeArgsNoReturnWithError(
            .HSM,
            @enumToInt(HSM_FID.HART_SUSPEND),
            @intCast(isize, @enumToInt(suspend_type)),
            @bitCast(isize, resume_addr),
            @bitCast(isize, value),
            error{ NOT_SUPPORTED, INVALID_PARAM, INVALID_ADDRESS, FAILED },
        );
    }

    pub const SuspendType = enum(u32) {
        /// Default retentive suspend
        RETENTIVE = 0,
        /// Default non-retentive suspend
        NON_RETENTIVE = 0x80000000,
        _,
    };

    pub const State = enum(isize) {
        /// The hart is physically powered-up and executing normally.
        STARTED = 0x0,
        /// The hart is not executing in supervisor-mode or any lower privilege mode. It is probably powered-down by the
        /// SBI implementation if the underlying platform has a mechanism to physically power-down harts.
        STOPPED = 0x1,
        /// Some other hart has requested to start (or power-up) the hart from the `STOPPED` state and the SBI
        /// implementation is still working to get the hart in the `STARTED` state.
        START_PENDING = 0x2,
        /// The hart has requested to stop (or power-down) itself from the `STARTED` state and the SBI implementation is
        /// still working to get the hart in the `STOPPED` state.
        STOP_PENDING = 0x3,
        /// This hart is in a platform specific suspend (or low power) state.
        SUSPENDED = 0x4,
        /// The hart has requested to put itself in a platform specific low power state from the STARTED state and the SBI
        /// implementation is still working to get the hart in the platform specific SUSPENDED state.
        SUSPEND_PENDING = 0x5,
        /// An interrupt or platform specific hardware event has caused the hart to resume normal execution from the
        /// `SUSPENDED` state and the SBI implementation is still working to get the hart in the `STARTED` state.
        RESUME_PENDING = 0x6,
    };

    const HSM_FID = enum(i32) {
        HART_START = 0x0,
        HART_STOP = 0x1,
        HART_GET_STATUS = 0x2,
        HART_SUSPEND = 0x3,
    };

    comptime {
        std.testing.refAllDecls(@This());
    }
};

/// The System Reset Extension provides a function that allow the supervisor software to request system-level
/// reboot or shutdown.
/// The term "system" refers to the world-view of supervisor software and the underlying SBI implementation
/// could be machine mode firmware or hypervisor.
pub const reset = struct {
    pub fn available() bool {
        return base.probeExtension(.SRST);
    }

    /// Reset the system based on provided `reset_type` and `reset_reason`.
    /// This is a synchronous call and does not return if it succeeds.
    ///
    /// When supervisor software is running natively, the SBI implementation is machine mode firmware.
    /// In this case, shutdown is equivalent to physical power down of the entire system and cold reboot is
    /// equivalent to physical power cycle of the entire system. Further, warm reboot is equivalent to a power
    /// cycle of main processor and parts of the system but not the entire system. For example, on a server
    /// class system with a BMC (board management controller), a warm reboot will not power cycle the BMC
    /// whereas a cold reboot will definitely power cycle the BMC.
    ///
    /// When supervisor software is running inside a virtual machine, the SBI implementation is a hypervisor.
    /// The shutdown, cold reboot and warm reboot will behave functionally the same as the native case but
    /// might not result in any physical power changes.
    pub fn systemReset(
        reset_type: ResetType,
        reset_reason: ResetReason,
    ) error{ NOT_SUPPORTED, INVALID_PARAM, FAILED }!void {
        try ecall.twoArgsNoReturnWithError(
            .SRST,
            @enumToInt(SRST_FID.RESET),
            @intCast(isize, @enumToInt(reset_type)),
            @intCast(isize, @enumToInt(reset_reason)),
            error{ NOT_SUPPORTED, INVALID_PARAM, FAILED },
        );
        unreachable;
    }

    pub const ResetType = enum(u32) {
        SHUTDOWN = 0x0,
        COLD_REBOOT = 0x1,
        WARM_REBOOT = 0x2,
        _,
    };

    pub const ResetReason = enum(u32) {
        NONE = 0x0,
        SYSFAIL = 0x1,
        _,
    };

    const SRST_FID = enum(i32) {
        RESET = 0x0,
    };

    comptime {
        std.testing.refAllDecls(@This());
    }
};

pub const pmu = struct {
    pub fn available() bool {
        return base.probeExtension(.PMU);
    }

    /// Returns the number of counters (both hardware and firmware)
    pub fn getNumberOfCounters() usize {
        if (runtime_safety) {
            return @bitCast(usize, ecall.zeroArgsWithReturnWithError(
                .PMU,
                @enumToInt(PMU_FID.NUM_COUNTERS),
                error{NOT_SUPPORTED},
            ) catch unreachable);
        }

        return @bitCast(usize, ecall.zeroArgsWithReturnNoError(.PMU, @enumToInt(PMU_FID.NUM_COUNTERS)));
    }

    /// Get details about the specified counter such as underlying CSR number, width of the counter, type of
    /// counter hardware/firmware, etc.
    pub fn getCounterInfo(counter_index: usize) error{INVALID_PARAM}!CounterInfo {
        if (runtime_safety) {
            return @bitCast(CounterInfo, ecall.oneArgsWithReturnWithError(
                .PMU,
                @enumToInt(PMU_FID.COUNTER_GET_INFO),
                @bitCast(isize, counter_index),
                error{ NOT_SUPPORTED, INVALID_PARAM },
            ) catch |err| switch (err) {
                error.NOT_SUPPORTED => unreachable,
                else => |e| return e,
            });
        }

        return @bitCast(CounterInfo, try ecall.oneArgsWithReturnWithError(
            .PMU,
            @enumToInt(PMU_FID.COUNTER_GET_INFO),
            @bitCast(isize, counter_index),
            error{INVALID_PARAM},
        ));
    }

    /// Find and configure a counter from a set of counters which is not started (or enabled) and can monitor
    /// the specified event.
    pub fn configureMatchingCounter(
        counter_base: usize,
        counter_mask: usize,
        config_flags: ConfigFlags,
        event: Event,
    ) error{ NOT_SUPPORTED, INVALID_PARAM }!usize {
        const event_data = event.toEventData();

        return @bitCast(usize, try ecall.fiveArgsLastArg64WithReturnWithError(
            .PMU,
            @enumToInt(PMU_FID.COUNTER_CFG_MATCH),
            @bitCast(isize, counter_base),
            @bitCast(isize, counter_mask),
            @bitCast(isize, config_flags),
            @bitCast(isize, event_data.event_index),
            event_data.event_data,
            error{ NOT_SUPPORTED, INVALID_PARAM },
        ));
    }

    /// Start or enable a set of counters on the calling HART with the specified initial value.
    /// The `counter_mask` parameter represent the set of counters whereas the `initial_value` parameter
    /// specifies the initial value of the counter (if `start_flags.INIT_VALUE` is set).
    pub fn startCounters(
        counter_base: usize,
        counter_mask: usize,
        start_flags: StartFlags,
        initial_value: u64,
    ) error{ INVALID_PARAM, ALREADY_STARTED }!void {
        if (runtime_safety) {
            ecall.fourArgsLastArg64NoReturnWithError(
                .PMU,
                @enumToInt(PMU_FID.COUNTER_START),
                @bitCast(isize, counter_base),
                @bitCast(isize, counter_mask),
                @bitCast(isize, start_flags),
                initial_value,
                error{ NOT_SUPPORTED, INVALID_PARAM, ALREADY_STARTED },
            ) catch |err| switch (err) {
                error.NOT_SUPPORTED => unreachable,
                else => |e| return e,
            };

            return;
        }

        return ecall.fourArgsLastArg64NoReturnWithError(
            .PMU,
            @enumToInt(PMU_FID.COUNTER_START),
            @bitCast(isize, counter_base),
            @bitCast(isize, counter_mask),
            @bitCast(isize, start_flags),
            initial_value,
            error{ INVALID_PARAM, ALREADY_STARTED },
        );
    }

    /// Stop or disable a set of counters on the calling HART. The `counter_mask` parameter represent the set of counters.
    pub fn stopCounters(
        counter_base: usize,
        counter_mask: usize,
        stop_flags: StopFlags,
    ) error{ INVALID_PARAM, ALREADY_STOPPED }!void {
        if (runtime_safety) {
            ecall.threeArgsNoReturnWithError(
                .PMU,
                @enumToInt(PMU_FID.COUNTER_START),
                @bitCast(isize, counter_base),
                @bitCast(isize, counter_mask),
                @bitCast(isize, stop_flags),
                error{ NOT_SUPPORTED, INVALID_PARAM, ALREADY_STOPPED },
            ) catch |err| switch (err) {
                error.NOT_SUPPORTED => unreachable,
                else => |e| return e,
            };

            return;
        }

        return ecall.threeArgsNoReturnWithError(
            .PMU,
            @enumToInt(PMU_FID.COUNTER_START),
            @bitCast(isize, counter_base),
            @bitCast(isize, counter_mask),
            @bitCast(isize, stop_flags),
            error{ INVALID_PARAM, ALREADY_STOPPED },
        );
    }

    /// Provide the current value of a firmware counter.
    pub fn readFirmwareCounter(counter_index: usize) error{INVALID_PARAM}!usize {
        if (runtime_safety) {
            return @bitCast(usize, ecall.oneArgsWithReturnWithError(
                .PMU,
                @enumToInt(PMU_FID.COUNTER_FW_READ),
                @bitCast(isize, counter_index),
                error{ NOT_SUPPORTED, INVALID_PARAM },
            ) catch |err| switch (err) {
                error.NOT_SUPPORTED => unreachable,
                else => |e| return e,
            });
        }

        return @bitCast(usize, try ecall.oneArgsWithReturnWithError(
            .PMU,
            @enumToInt(PMU_FID.COUNTER_FW_READ),
            @bitCast(isize, counter_index),
            error{INVALID_PARAM},
        ));
    }

    pub const Event = union(EventType) {
        HW: HW_EVENT,
        HW_CACHE: HW_CACHE_EVENT,
        HW_RAW: if (is_64) u48 else u32,
        FW: FW_EVENT,

        pub const EventType = enum(u4) {
            HW = 0x0,
            HW_CACHE = 0x1,
            HW_RAW = 0x2,
            FW = 0xf,
        };

        pub const HW_EVENT = enum(u16) {
            /// Event for each CPU cycle
            CPU_CYCLES = 1,
            /// Event for each completed instruction
            INSTRUCTIONS = 2,
            /// Event for cache hit
            CACHE_REFERENCES = 3,
            /// Event for cache miss
            CACHE_MISSES = 4,
            /// Event for a branch instruction
            BRANCH_INSTRUCTIONS = 5,
            /// Event for a branch misprediction
            BRANCH_MISSES = 6,
            /// Event for each BUS cycle
            BUS_CYCLES = 7,
            /// Event for a stalled cycle in microarchitecture frontend
            STALLED_CYCLES_FRONTEND = 8,
            /// Event for a stalled cycle in microarchitecture backend
            STALLED_CYCLES_BACKEND = 9,
            /// Event for each reference CPU cycle
            REF_CPU_CYCLES = 10,

            _,
        };

        pub const HW_CACHE_EVENT = packed struct {
            result_id: ResultId,
            op_id: OpId,
            cache_id: CacheId,

            pub const ResultId = enum(u1) {
                ACCESS = 0,
                MISS = 1,
            };

            pub const OpId = enum(u2) {
                READ = 0,
                WRITE = 1,
                PREFETCH = 2,
            };

            pub const CacheId = enum(u13) {
                /// Level1 data cache event
                L1D = 0,
                /// Level1 instruction cache event
                L1I = 1,
                /// Last level cache event
                LL = 2,
                /// Data TLB event
                DTLB = 3,
                /// Instruction TLB event
                ITLB = 4,
                /// Branch predictor unit event
                BPU = 5,
                /// NUMA node cache event
                NODE = 6,
            };

            comptime {
                std.debug.assert(@sizeOf(u16) == @sizeOf(HW_CACHE_EVENT));
                std.debug.assert(@bitSizeOf(u16) == @bitSizeOf(HW_CACHE_EVENT));
            }

            comptime {
                std.testing.refAllDecls(@This());
            }
        };

        pub const FW_EVENT = enum(u16) {
            MISALIGNED_LOAD = 0,
            MISALIGNED_STORE = 1,
            ACCESS_LOAD = 2,
            ACCESS_STORE = 3,
            ILLEGAL_INSN = 4,
            SET_TIMER = 5,
            IPI_SENT = 6,
            IPI_RECVD = 7,
            FENCE_I_SENT = 8,
            FENCE_I_RECVD = 9,
            SFENCE_VMA_SENT = 10,
            SFENCE_VMA_RCVD = 11,
            SFENCE_VMA_ASID_SENT = 12,
            SFENCE_VMA_ASID_RCVD = 13,
            HFENCE_GVMA_SENT = 14,
            HFENCE_GVMA_RCVD = 15,
            HFENCE_GVMA_VMID_SENT = 16,
            HFENCE_GVMA_VMID_RCVD = 17,
            HFENCE_VVMA_SENT = 18,
            HFENCE_VVMA_RCVD = 19,
            HFENCE_VVMA_ASID_SENT = 20,
            HFENCE_VVMA_ASID_RCVD = 21,

            _,
        };

        fn toEventData(self: Event) EventData {
            return switch (self) {
                .HW => |hw| EventData{
                    .event_index = @as(u20, @enumToInt(hw)) | (@as(u20, @enumToInt(EventType.HW)) << 16),
                    .event_data = 0,
                },
                .HW_CACHE => |hw_cache| EventData{
                    .event_index = @as(u20, @bitCast(u16, hw_cache)) | (@as(u20, @enumToInt(EventType.HW_CACHE)) << 16),
                    .event_data = 0,
                },
                .HW_RAW => |hw_raw| EventData{
                    .event_index = @as(u20, @enumToInt(EventType.HW_RAW)) << 16,
                    .event_data = hw_raw,
                },
                .FW => |fw| EventData{
                    .event_index = @as(u20, @enumToInt(fw)) | (@as(u20, @enumToInt(EventType.FW)) << 16),
                    .event_data = 0,
                },
            };
        }

        const EventData = struct {
            event_index: usize,
            event_data: u64,
        };

        comptime {
            std.testing.refAllDecls(@This());
        }
    };

    pub const ConfigFlags = packed struct {
        /// Skip the counter matching
        SKIP_MATCH: bool = false,
        /// Clear (or zero) the counter value in counter configuration
        CLEAR_VALUE: bool = false,
        /// Start the counter after configuring a matching counter
        AUTO_START: bool = false,
        /// Event counting inhibited in VU-mode
        SET_VUINH: bool = false,
        /// Event counting inhibited in VS-mode
        SET_VSINH: bool = false,
        /// Event counting inhibited in U-mode
        SET_UINH: bool = false,
        /// Event counting inhibited in S-mode
        SET_SINH: bool = false,
        /// Event counting inhibited in M-mode
        SET_MINH: bool = false,

        // Packed structs in zig stage1 are so annoying
        _reserved1: u8 = 0,
        _reserved2: u16 = 0,
        _reserved3: if (is_64) u32 else u0 = 0,

        comptime {
            std.debug.assert(@sizeOf(usize) == @sizeOf(ConfigFlags));
            std.debug.assert(@bitSizeOf(usize) == @bitSizeOf(ConfigFlags));
        }

        comptime {
            std.testing.refAllDecls(@This());
        }
    };

    pub const StartFlags = packed struct {
        /// Set the value of counters based on the `initial_value` parameter
        INIT_VALUE: bool = false,

        _reserved: if (is_64) u63 else u31 = 0,

        comptime {
            std.debug.assert(@sizeOf(usize) == @sizeOf(StartFlags));
            std.debug.assert(@bitSizeOf(usize) == @bitSizeOf(StartFlags));
        }

        comptime {
            std.testing.refAllDecls(@This());
        }
    };

    pub const StopFlags = packed struct {
        /// Reset the counter to event mapping.
        RESET: bool = false,

        _reserved: if (is_64) u63 else u31 = 0,

        comptime {
            std.debug.assert(@sizeOf(usize) == @sizeOf(StopFlags));
            std.debug.assert(@bitSizeOf(usize) == @bitSizeOf(StopFlags));
        }

        comptime {
            std.testing.refAllDecls(@This());
        }
    };

    /// If `type` is `.firmware` `csr` and `width` should be ignored.
    pub const CounterInfo = packed struct {
        csr: u12,
        /// Width (One less than number of bits in CSR)
        width: u6,
        _reserved: if (is_64) u45 else u13,
        type: CounterType,

        pub const CounterType = enum(u1) {
            hardware = 0,
            firmware = 1,
        };

        comptime {
            std.debug.assert(@sizeOf(usize) == @sizeOf(CounterInfo));
            std.debug.assert(@bitSizeOf(usize) == @bitSizeOf(CounterInfo));
        }

        comptime {
            std.testing.refAllDecls(@This());
        }
    };

    const PMU_FID = enum(i32) {
        NUM_COUNTERS = 0x0,
        COUNTER_GET_INFO = 0x1,
        COUNTER_CFG_MATCH = 0x2,
        COUNTER_START = 0x3,
        COUNTER_STOP = 0x4,
        COUNTER_FW_READ = 0x5,
    };

    comptime {
        std.testing.refAllDecls(@This());
    }
};

const ecall = struct {
    inline fn zeroArgsNoReturnWithError(eid: EID, fid: i32, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;
        asm volatile ("ecall"
            : [err] "={x10}" (err),
            : [eid] "{x17}" (@enumToInt(eid)),
              [fid] "{x16}" (fid),
            : "x11"
        );
        if (err == .SUCCESS) return;
        return err.toError(ErrorT);
    }

    inline fn zeroArgsWithReturnWithError(eid: EID, fid: i32, comptime ErrorT: type) ErrorT!isize {
        var err: ErrorCode = undefined;
        var value: isize = undefined;
        asm volatile ("ecall"
            : [err] "={x10}" (err),
              [value] "={x11}" (value),
            : [eid] "{x17}" (@enumToInt(eid)),
              [fid] "{x16}" (fid),
        );
        if (err == .SUCCESS) return value;
        return err.toError(ErrorT);
    }

    inline fn zeroArgsWithReturnNoError(eid: EID, fid: i32) isize {
        return asm volatile ("ecall"
            : [value] "={x11}" (-> isize),
            : [eid] "{x17}" (@enumToInt(eid)),
              [fid] "{x16}" (fid),
            : "x10"
        );
    }

    inline fn oneArgsWithReturnWithError(eid: EID, fid: i32, a0: isize, comptime ErrorT: type) ErrorT!isize {
        var err: ErrorCode = undefined;
        var value: isize = undefined;
        asm volatile ("ecall"
            : [err] "={x10}" (err),
              [value] "={x11}" (value),
            : [eid] "{x17}" (@enumToInt(eid)),
              [fid] "{x16}" (fid),
              [arg0] "{x10}" (a0),
        );
        if (err == .SUCCESS) return value;
        return err.toError(ErrorT);
    }

    inline fn oneArgsWithReturnNoError(eid: EID, fid: i32, a0: isize) isize {
        return asm volatile ("ecall"
            : [value] "={x11}" (-> isize),
            : [eid] "{x17}" (@enumToInt(eid)),
              [fid] "{x16}" (fid),
              [arg0] "{x10}" (a0),
            : "x10"
        );
    }

    inline fn oneArgs64NoReturnNoError(eid: EID, fid: i32, a0: u64) void {
        if (is_64) {
            asm volatile ("ecall"
                :
                : [eid] "{x17}" (@enumToInt(eid)),
                  [fid] "{x16}" (fid),
                  [arg0] "{x10}" (a0),
                : "x11", "x10"
            );
        } else {
            asm volatile ("ecall"
                :
                : [eid] "{x17}" (@enumToInt(eid)),
                  [fid] "{x16}" (fid),
                  [arg0_lo] "{x10}" (@truncate(u32, a0)),
                  [arg0_hi] "{x11}" (@truncate(u32, a0 >> 32)),
                : "x11", "x10"
            );
        }
    }

    inline fn oneArgs64NoReturnWithError(eid: EID, fid: i32, a0: u64, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;
        if (is_64) {
            asm volatile ("ecall"
                : [err] "={x10}" (err),
                : [eid] "{x17}" (@enumToInt(eid)),
                  [fid] "{x16}" (fid),
                  [arg0] "{x10}" (a0),
                : "x11"
            );
        } else {
            asm volatile ("ecall"
                : [err] "={x10}" (err),
                : [eid] "{x17}" (@enumToInt(eid)),
                  [fid] "{x16}" (fid),
                  [arg0_lo] "{x10}" (@truncate(u32, a0)),
                  [arg0_hi] "{x11}" (@truncate(u32, a0 >> 32)),
                : "x11"
            );
        }

        if (err == .SUCCESS) return;
        return err.toError(ErrorT);
    }

    inline fn legacyOneArgs64NoReturnNoError(eid: EID, a0: u64) void {
        if (is_64) {
            asm volatile ("ecall"
                :
                : [eid] "{x17}" (@enumToInt(eid)),
                  [arg0] "{x10}" (a0),
                : "x10"
            );
        } else {
            asm volatile ("ecall"
                :
                : [eid] "{x17}" (@enumToInt(eid)),
                  [arg0_lo] "{x10}" (@truncate(u32, a0)),
                  [arg0_hi] "{x11}" (@truncate(u32, a0 >> 32)),
                : "x10"
            );
        }
    }

    inline fn legacyOneArgs64NoReturnWithRawError(eid: EID, a0: u64) ImplementationDefinedError {
        var err: ImplementationDefinedError = undefined;

        if (is_64) {
            asm volatile ("ecall"
                : [err] "={x10}" (err),
                : [eid] "{x17}" (@enumToInt(eid)),
                  [arg0] "{x10}" (a0),
            );
        } else {
            asm volatile ("ecall"
                : [err] "={x10}" (err),
                : [eid] "{x17}" (@enumToInt(eid)),
                  [arg0_lo] "{x10}" (@truncate(u32, a0)),
                  [arg0_hi] "{x11}" (@truncate(u32, a0 >> 32)),
            );
        }

        return err;
    }

    inline fn legacyOneArgs64NoReturnWithError(eid: EID, a0: u64, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;
        if (is_64) {
            asm volatile ("ecall"
                : [err] "={x10}" (err),
                : [eid] "{x17}" (@enumToInt(eid)),
                  [arg0] "{x10}" (a0),
            );
        } else {
            asm volatile ("ecall"
                : [err] "={x10}" (err),
                : [eid] "{x17}" (@enumToInt(eid)),
                  [arg0_lo] "{x10}" (@truncate(u32, a0)),
                  [arg0_hi] "{x11}" (@truncate(u32, a0 >> 32)),
            );
        }

        if (err == .SUCCESS) return;
        return err.toError(ErrorT);
    }

    inline fn legacyOneArgsNoReturnNoError(eid: EID, a0: isize) void {
        asm volatile ("ecall"
            :
            : [eid] "{x17}" (@enumToInt(eid)),
              [arg0] "{x10}" (a0),
            : "x10"
        );
    }

    inline fn legacyOneArgsNoReturnWithRawError(eid: EID, a0: isize) ImplementationDefinedError {
        var err: ImplementationDefinedError = undefined;
        asm volatile ("ecall"
            : [err] "={x10}" (err),
            : [eid] "{x17}" (@enumToInt(eid)),
              [arg0] "{x10}" (a0),
        );
        return err;
    }

    inline fn legacyOneArgsNoReturnWithError(eid: EID, a0: isize, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;
        asm volatile ("ecall"
            : [err] "={x10}" (err),
            : [eid] "{x17}" (@enumToInt(eid)),
              [arg0] "{x10}" (a0),
        );
        if (err == .SUCCESS) return;
        return err.toError(ErrorT);
    }

    inline fn legacyThreeArgsNoReturnNoError(eid: EID, a0: isize, a1: isize, a2: isize) void {
        asm volatile ("ecall"
            :
            : [eid] "{x17}" (@enumToInt(eid)),
              [arg0] "{x10}" (a0),
              [arg1] "{x11}" (a1),
              [arg2] "{x12}" (a2),
            : "x10"
        );
    }

    inline fn legacyThreeArgsNoReturnWithError(eid: EID, a0: isize, a1: isize, a2: isize, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;
        asm volatile ("ecall"
            : [err] "={x10}" (err),
            : [eid] "{x17}" (@enumToInt(eid)),
              [arg0] "{x10}" (a0),
              [arg1] "{x11}" (a1),
              [arg2] "{x12}" (a2),
        );

        if (err == .SUCCESS) return;
        return err.toError(ErrorT);
    }

    inline fn legacyFourArgsNoReturnWithRawError(eid: EID, a0: isize, a1: isize, a2: isize, a3: isize) ImplementationDefinedError {
        var err: ImplementationDefinedError = undefined;
        asm volatile ("ecall"
            : [err] "={x10}" (err),
            : [eid] "{x17}" (@enumToInt(eid)),
              [arg0] "{x10}" (a0),
              [arg1] "{x11}" (a1),
              [arg2] "{x12}" (a2),
              [arg3] "{x13}" (a3),
        );

        return err;
    }

    inline fn legacyFourArgsNoReturnWithError(eid: EID, a0: isize, a1: isize, a2: isize, a3: isize, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;
        asm volatile ("ecall"
            : [err] "={x10}" (err),
            : [eid] "{x17}" (@enumToInt(eid)),
              [arg0] "{x10}" (a0),
              [arg1] "{x11}" (a1),
              [arg2] "{x12}" (a2),
              [arg3] "{x13}" (a3),
        );

        if (err == .SUCCESS) return;
        return err.toError(ErrorT);
    }

    inline fn legacyFourArgsNoReturnNoError(eid: EID, a0: isize, a1: isize, a2: isize, a3: isize) void {
        asm volatile ("ecall"
            :
            : [eid] "{x17}" (@enumToInt(eid)),
              [arg0] "{x10}" (a0),
              [arg1] "{x11}" (a1),
              [arg2] "{x12}" (a2),
              [arg3] "{x13}" (a3),
            : "x10"
        );
    }

    inline fn legacyZeroArgsWithReturnWithError(eid: EID, comptime ErrorT: type) ErrorT!isize {
        var val: isize = undefined;
        asm volatile ("ecall"
            : [val] "={x10}" (val),
            : [eid] "{x17}" (@enumToInt(eid)),
        );
        if (val >= 0) return val;
        return @intToEnum(ErrorCode, val).toError(ErrorT);
    }

    inline fn legacyZeroArgsNoReturnWithError(eid: EID, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;
        asm volatile ("ecall"
            : [err] "={x10}" (err),
            : [eid] "{x17}" (@enumToInt(eid)),
        );
        if (err == .SUCCESS) return;
        return err.toError(ErrorT);
    }

    inline fn legacyZeroArgsNoReturnNoError(eid: EID) void {
        asm volatile ("ecall"
            :
            : [eid] "{x17}" (@enumToInt(eid)),
            : "x10"
        );
    }

    inline fn twoArgsNoReturnWithError(eid: EID, fid: i32, a0: isize, a1: isize, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;
        asm volatile ("ecall"
            : [err] "={x10}" (err),
            : [eid] "{x17}" (@enumToInt(eid)),
              [fid] "{x16}" (fid),
              [arg0] "{x10}" (a0),
              [arg1] "{x11}" (a1),
            : "x11"
        );
        if (err == .SUCCESS) return;
        return err.toError(ErrorT);
    }

    inline fn fourArgsLastArg64NoReturnWithError(
        eid: EID,
        fid: i32,
        a0: isize,
        a1: isize,
        a2: isize,
        a3: u64,
        comptime ErrorT: type,
    ) ErrorT!void {
        var err: ErrorCode = undefined;

        if (is_64) {
            asm volatile ("ecall"
                : [err] "={x10}" (err),
                : [eid] "{x17}" (@enumToInt(eid)),
                  [fid] "{x16}" (fid),
                  [arg0] "{x10}" (a0),
                  [arg1] "{x11}" (a1),
                  [arg2] "{x12}" (a2),
                  [arg3] "{x13}" (a3),
                : "x11"
            );
        } else {
            asm volatile ("ecall"
                : [err] "={x10}" (err),
                : [eid] "{x17}" (@enumToInt(eid)),
                  [fid] "{x16}" (fid),
                  [arg0] "{x10}" (a0),
                  [arg1] "{x11}" (a1),
                  [arg2] "{x12}" (a2),
                  [arg3_lo] "{x13}" (@truncate(u32, a3)),
                  [arg3_hi] "{x14}" (@truncate(u32, a3 >> 32)),
                : "x11"
            );
        }

        if (err == .SUCCESS) return;
        return err.toError(ErrorT);
    }

    inline fn fourArgsNoReturnWithError(eid: EID, fid: i32, a0: isize, a1: isize, a2: isize, a3: isize, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;
        asm volatile ("ecall"
            : [err] "={x10}" (err),
            : [eid] "{x17}" (@enumToInt(eid)),
              [fid] "{x16}" (fid),
              [arg0] "{x10}" (a0),
              [arg1] "{x11}" (a1),
              [arg2] "{x12}" (a2),
              [arg3] "{x13}" (a3),
            : "x11"
        );
        if (err == .SUCCESS) return;
        return err.toError(ErrorT);
    }

    inline fn fiveArgsLastArg64WithReturnWithError(
        eid: EID,
        fid: i32,
        a0: isize,
        a1: isize,
        a2: isize,
        a3: isize,
        a4: u64,
        comptime ErrorT: type,
    ) ErrorT!isize {
        var err: ErrorCode = undefined;
        var value: isize = undefined;

        if (is_64) {
            asm volatile ("ecall"
                : [err] "={x10}" (err),
                  [value] "={x11}" (value),
                : [eid] "{x17}" (@enumToInt(eid)),
                  [fid] "{x16}" (fid),
                  [arg0] "{x10}" (a0),
                  [arg1] "{x11}" (a1),
                  [arg2] "{x12}" (a2),
                  [arg3] "{x13}" (a3),
                  [arg4] "{x14}" (a4),
            );
        } else {
            asm volatile ("ecall"
                : [err] "={x10}" (err),
                  [value] "={x11}" (value),
                : [eid] "{x17}" (@enumToInt(eid)),
                  [fid] "{x16}" (fid),
                  [arg0] "{x10}" (a0),
                  [arg1] "{x11}" (a1),
                  [arg2] "{x12}" (a2),
                  [arg3] "{x13}" (a3),
                  [arg4_lo] "{x14}" (@truncate(u32, a4)),
                  [arg4_hi] "{x15}" (@truncate(u32, a4 >> 32)),
            );
        }

        if (err == .SUCCESS) return value;
        return err.toError(ErrorT);
    }

    inline fn fiveArgsNoReturnWithError(eid: EID, fid: i32, a0: isize, a1: isize, a2: isize, a3: isize, a4: isize, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;
        asm volatile ("ecall"
            : [err] "={x10}" (err),
            : [eid] "{x17}" (@enumToInt(eid)),
              [fid] "{x16}" (fid),
              [arg0] "{x10}" (a0),
              [arg1] "{x11}" (a1),
              [arg2] "{x12}" (a2),
              [arg3] "{x13}" (a3),
              [arg4] "{x14}" (a4),
            : "x11"
        );
        if (err == .SUCCESS) return;
        return err.toError(ErrorT);
    }

    inline fn threeArgsNoReturnWithError(eid: EID, fid: i32, a0: isize, a1: isize, a2: isize, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;
        asm volatile ("ecall"
            : [err] "={x10}" (err),
            : [eid] "{x17}" (@enumToInt(eid)),
              [fid] "{x16}" (fid),
              [arg0] "{x10}" (a0),
              [arg1] "{x11}" (a1),
              [arg2] "{x12}" (a2),
            : "x11"
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
        );
        if (err == .SUCCESS) return value;
        return err.toError(ErrorT);
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

pub const ImplementationDefinedError = enum(isize) {
    SUCCESS = 0,

    _,
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
        const errors: []const std.builtin.Type.Error = @typeInfo(ErrorT).ErrorSet.?;
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
