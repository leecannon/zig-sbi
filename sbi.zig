// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

/// The base extension is designed to be as small as possible.
///
/// As such, it only contains functionality for probing which SBI extensions are available and for querying the version
/// of the SBI.
///
/// All functions in the base extension must be supported by all SBI implementations, so there are no error returns
/// defined.
pub const base = struct {
    /// Returns the current SBI specification version.
    pub fn getSpecVersion() SpecVersion {
        return @bitCast(ecall.zeroArgsWithReturnNoError(
            .BASE,
            @intFromEnum(BASE_FID.GET_SPEC_VERSION),
        ));
    }

    /// Returns the current SBI implementation ID, which is different for every SBI implementation.
    ///
    /// It is intended that this implementation ID allows software to probe for SBI implementation quirks
    pub fn getImplementationId() ImplementationId {
        return @enumFromInt(ecall.zeroArgsWithReturnNoError(
            .BASE,
            @intFromEnum(BASE_FID.GET_IMP_ID),
        ));
    }

    /// Returns the current SBI implementation version.
    ///
    /// The encoding of this version number is specific to the SBI implementation.
    pub fn getImplementationVersion() isize {
        return ecall.zeroArgsWithReturnNoError(
            .BASE,
            @intFromEnum(BASE_FID.GET_IMP_VERSION),
        );
    }

    /// Returns false if the given SBI extension ID (EID) is not available, or true if it is available.
    pub fn probeExtension(eid: EID) bool {
        return ecall.oneArgsWithReturnNoError(
            .BASE,
            @intFromEnum(BASE_FID.PROBE_EXT),
            @intFromEnum(eid),
        ) != 0;
    }

    /// Return a value that is legal for the `mvendorid` CSR and 0 is always a legal value for this CSR.
    pub fn machineVendorId() isize {
        return ecall.zeroArgsWithReturnNoError(
            .BASE,
            @intFromEnum(BASE_FID.GET_MVENDORID),
        );
    }

    /// Return a value that is legal for the `marchid` CSR and 0 is always a legal value for this CSR.
    pub fn machineArchId() isize {
        return ecall.zeroArgsWithReturnNoError(
            .BASE,
            @intFromEnum(BASE_FID.GET_MARCHID),
        );
    }

    /// Return a value that is legal for the `mimpid` CSR and 0 is always a legal value for this CSR.
    pub fn machineImplementationId() isize {
        return ecall.zeroArgsWithReturnNoError(
            .BASE,
            @intFromEnum(BASE_FID.GET_MIMPID),
        );
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

    pub const SpecVersion = packed struct(usize) {
        minor: u24,
        major: u7,
        _reserved: u1,
        _: if (is_64) u32 else u0,
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
};

pub const time = struct {
    pub fn available() bool {
        return base.probeExtension(.TIME);
    }

    /// Programs the clock for next event after `time_value` time.
    ///
    /// This function also clears the pending timer interrupt bit.
    ///
    /// If the supervisor wishes to clear the timer interrupt without scheduling the next timer event, it can either
    /// request a timer interrupt infinitely far into the future (i.e., `setTimer(std.math.maxInt(u64))`), or it can
    /// instead mask the timer interrupt by clearing `sie.STIE` CSR bit.
    pub fn setTimer(time_value: u64) void {
        if (runtime_safety) {
            ecall.oneArgs64NoReturnWithError(
                .TIME,
                @intFromEnum(TIME_FID.TIME_SET_TIMER),
                time_value,
                error{NotSupported},
            ) catch unreachable;
            return;
        }

        ecall.oneArgs64NoReturnNoError(
            .TIME,
            @intFromEnum(TIME_FID.TIME_SET_TIMER),
            time_value,
        );
    }

    const TIME_FID = enum(i32) {
        TIME_SET_TIMER = 0x0,
    };
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

    pub const SendIPIError = error{InvalidParameter};

    /// Send an inter-processor interrupt to all the harts defined in `hart_mask`.
    ///
    /// Interprocessor interrupts manifest at the receiving harts as the supervisor software interrupts.
    pub fn sendIPI(hart_mask: HartMask) SendIPIError!void {
        var bit_mask: isize = undefined;
        var mask_base: isize = undefined;

        switch (hart_mask) {
            .all => {
                bit_mask = 0;
                mask_base = 0;
            },
            .mask => |mask| {
                bit_mask = @bitCast(mask.mask);
                mask_base = @bitCast(mask.base);
            },
        }

        if (runtime_safety) {
            ecall.twoArgsNoReturnWithError(
                .IPI,
                @intFromEnum(IPI_FID.SEND_IPI),
                bit_mask,
                mask_base,
                SendIPIError || error{NotSupported},
            ) catch |err| switch (err) {
                error.NotSupported => unreachable,
                else => |e| return e,
            };

            return;
        }

        return ecall.twoArgsNoReturnWithError(
            .IPI,
            @intFromEnum(IPI_FID.SEND_IPI),
            bit_mask,
            mask_base,
            SendIPIError,
        );
    }

    const IPI_FID = enum(i32) {
        SEND_IPI = 0x0,
    };
};

/// Any function that wishes to use range of addresses (i.e. `start_addr` and `size`), have to abide by the below
/// constraints on range parameters.
///
/// The remote fence function acts as a full TLB flush if
///  - `start_addr` and `size` are both `0`
///  - `size` is equal to `2^XLEN-1`
pub const rfence = struct {
    pub fn available() bool {
        return base.probeExtension(.RFENCE);
    }

    pub const RemoteFenceIError = error{InvalidParameter};

    /// Instructs remote harts to execute FENCE.I instruction.
    pub fn remoteFenceI(hart_mask: HartMask) RemoteFenceIError!void {
        var bit_mask: isize = undefined;
        var mask_base: isize = undefined;

        switch (hart_mask) {
            .all => {
                bit_mask = 0;
                mask_base = 0;
            },
            .mask => |mask| {
                bit_mask = @bitCast(mask.mask);
                mask_base = @bitCast(mask.base);
            },
        }

        if (runtime_safety) {
            ecall.twoArgsNoReturnWithError(
                .RFENCE,
                @intFromEnum(RFENCE_FID.FENCE_I),
                bit_mask,
                mask_base,
                RemoteFenceIError || error{NotSupported},
            ) catch |err| switch (err) {
                error.NotSupported => unreachable,
                else => |e| return e,
            };

            return;
        }

        return ecall.twoArgsNoReturnWithError(
            .RFENCE,
            @intFromEnum(RFENCE_FID.FENCE_I),
            bit_mask,
            mask_base,
            RemoteFenceIError,
        );
    }

    pub const RemoteSFenceVMAError = error{ InvalidParameter, InvalidAddress };

    /// Instructs the remote harts to execute one or more SFENCE.VMA instructions, covering the range of
    /// virtual addresses between `start_addr` and `size`.
    pub fn remoteSFenceVMA(
        hart_mask: HartMask,
        start_addr: usize,
        size: usize,
    ) RemoteSFenceVMAError!void {
        var bit_mask: isize = undefined;
        var mask_base: isize = undefined;

        switch (hart_mask) {
            .all => {
                bit_mask = 0;
                mask_base = 0;
            },
            .mask => |mask| {
                bit_mask = @bitCast(mask.mask);
                mask_base = @bitCast(mask.base);
            },
        }

        if (runtime_safety) {
            ecall.fourArgsNoReturnWithError(
                .RFENCE,
                @intFromEnum(RFENCE_FID.SFENCE_VMA),
                bit_mask,
                mask_base,
                @bitCast(start_addr),
                @bitCast(size),
                RemoteSFenceVMAError || error{NotSupported},
            ) catch |err| switch (err) {
                error.NotSupported => unreachable,
                else => |e| return e,
            };

            return;
        }

        return ecall.fourArgsNoReturnWithError(
            .RFENCE,
            @intFromEnum(RFENCE_FID.SFENCE_VMA),
            bit_mask,
            mask_base,
            @bitCast(start_addr),
            @bitCast(size),
            RemoteSFenceVMAError,
        );
    }

    pub const RemoteSFenceVMAWithASIDError = error{ InvalidParameter, InvalidAddress };

    /// Instructs the remote harts to execute one or more SFENCE.VMA instructions, covering the range of virtual
    /// addresses between `start_addr` and `size`.
    ///
    /// This covers only the given ASID.
    pub fn remoteSFenceVMAWithASID(
        hart_mask: HartMask,
        start_addr: usize,
        size: usize,
        asid: usize,
    ) RemoteSFenceVMAWithASIDError!void {
        var bit_mask: isize = undefined;
        var mask_base: isize = undefined;

        switch (hart_mask) {
            .all => {
                bit_mask = 0;
                mask_base = 0;
            },
            .mask => |mask| {
                bit_mask = @bitCast(mask.mask);
                mask_base = @bitCast(mask.base);
            },
        }

        if (runtime_safety) {
            ecall.fiveArgsNoReturnWithError(
                .RFENCE,
                @intFromEnum(RFENCE_FID.SFENCE_VMA_ASID),
                bit_mask,
                mask_base,
                @bitCast(start_addr),
                @bitCast(size),
                @bitCast(asid),
                RemoteSFenceVMAWithASIDError || error{NotSupported},
            ) catch |err| switch (err) {
                error.NotSupported => unreachable,
                else => |e| return e,
            };

            return;
        }

        return ecall.fiveArgsNoReturnWithError(
            .RFENCE,
            @intFromEnum(RFENCE_FID.SFENCE_VMA_ASID),
            bit_mask,
            mask_base,
            @bitCast(start_addr),
            @bitCast(size),
            @bitCast(asid),
            RemoteSFenceVMAWithASIDError,
        );
    }

    pub const RemoteHFenceGVMAWithVMIDError = error{ NotSupported, InvalidParameter, InvalidAddress };

    /// Instruct the remote harts to execute one or more HFENCE.GVMA instructions, covering the range of guest physical
    /// addresses between start and size only for the given VMID.
    ///
    /// This function call is only valid for harts implementing hypervisor extension.
    pub fn remoteHFenceGVMAWithVMID(
        hart_mask: HartMask,
        start_addr: usize,
        size: usize,
        vmid: usize,
    ) RemoteHFenceGVMAWithVMIDError!void {
        var bit_mask: isize = undefined;
        var mask_base: isize = undefined;

        switch (hart_mask) {
            .all => {
                bit_mask = 0;
                mask_base = 0;
            },
            .mask => |mask| {
                bit_mask = @bitCast(mask.mask);
                mask_base = @bitCast(mask.base);
            },
        }

        return ecall.fiveArgsNoReturnWithError(
            .RFENCE,
            @intFromEnum(RFENCE_FID.HFENCE_GVMA_VMID),
            bit_mask,
            mask_base,
            @bitCast(start_addr),
            @bitCast(size),
            @bitCast(vmid),
            RemoteHFenceGVMAWithVMIDError,
        );
    }

    pub const RemoteHFenceGVMAError = error{ NotSupported, InvalidParameter, InvalidAddress };

    /// Instruct the remote harts to execute one or more HFENCE.GVMA instructions, covering the range of guest physical
    /// addresses between start and size only for all guests.
    ///
    /// This function call is only valid for harts implementing hypervisor extension.
    pub fn remoteHFenceGVMA(
        hart_mask: HartMask,
        start_addr: usize,
        size: usize,
    ) error{ NotSupported, InvalidParameter, InvalidAddress }!void {
        var bit_mask: isize = undefined;
        var mask_base: isize = undefined;

        switch (hart_mask) {
            .all => {
                bit_mask = 0;
                mask_base = 0;
            },
            .mask => |mask| {
                bit_mask = @bitCast(mask.mask);
                mask_base = @bitCast(mask.base);
            },
        }

        return ecall.fourArgsNoReturnWithError(
            .RFENCE,
            @intFromEnum(RFENCE_FID.HFENCE_GVMA),
            bit_mask,
            mask_base,
            @bitCast(start_addr),
            @bitCast(size),
            RemoteHFenceGVMAError,
        );
    }

    pub const RemoteHFenceVVMAWithASIDError = error{ NotSupported, InvalidParameter, InvalidAddress };

    /// Instruct the remote harts to execute one or more HFENCE.VVMA instructions, covering the range of guest virtual
    /// addresses between `start_addr` and `size` for the given ASID and current VMID (in hgatp CSR) of calling hart.
    ///
    /// This function call is only valid for harts implementing hypervisor extension.
    pub fn remoteHFenceVVMAWithASID(
        hart_mask: HartMask,
        start_addr: usize,
        size: usize,
        asid: usize,
    ) RemoteHFenceVVMAWithASIDError!void {
        var bit_mask: isize = undefined;
        var mask_base: isize = undefined;

        switch (hart_mask) {
            .all => {
                bit_mask = 0;
                mask_base = 0;
            },
            .mask => |mask| {
                bit_mask = @bitCast(mask.mask);
                mask_base = @bitCast(mask.base);
            },
        }

        return ecall.fiveArgsNoReturnWithError(
            .RFENCE,
            @intFromEnum(RFENCE_FID.HFENCE_VVMA_ASID),
            bit_mask,
            mask_base,
            @bitCast(start_addr),
            @bitCast(size),
            @bitCast(asid),
            RemoteHFenceVVMAWithASIDError,
        );
    }

    pub const RemoteHFenceVVMAError = error{ NotSupported, InvalidParameter, InvalidAddress };

    /// Instruct the remote harts to execute one or more HFENCE.VVMA instructions, covering the range of guest virtual
    /// addresses between `start_addr` and `size` for current VMID (in hgatp CSR) of calling hart.
    ///
    /// This function call is only valid for harts implementing hypervisor extension.
    pub fn remoteHFenceVVMA(
        hart_mask: HartMask,
        start_addr: usize,
        size: usize,
    ) RemoteHFenceVVMAError!void {
        var bit_mask: isize = undefined;
        var mask_base: isize = undefined;

        switch (hart_mask) {
            .all => {
                bit_mask = 0;
                mask_base = 0;
            },
            .mask => |mask| {
                bit_mask = @bitCast(mask.mask);
                mask_base = @bitCast(mask.base);
            },
        }

        return ecall.fourArgsNoReturnWithError(
            .RFENCE,
            @intFromEnum(RFENCE_FID.HFENCE_VVMA),
            bit_mask,
            mask_base,
            @bitCast(start_addr),
            @bitCast(size),
            RemoteHFenceVVMAError,
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
};

/// The Hart State Management (HSM) Extension introduces a set of hart states and a set of functions which allow the
/// supervisor-mode software to request a hart state change.
pub const hsm = struct {
    pub fn available() bool {
        return base.probeExtension(.HSM);
    }

    pub const HartStartError = error{ InvalidAddress, InvalidParameter, AlreadyAvailable, Failed };

    /// Request the SBI implementation to start executing the target hart in supervisor-mode at address specified by
    /// `start_addr` parameter with specific registers values described in the SBI Specification.
    ///
    /// This call is asynchronous — more specifically, `hartStart` may return before the target hart starts executing
    /// as long as the SBI implementation is capable of ensuring the return code is accurate.
    ///
    /// If the SBI implementation is a platform runtime firmware executing in machine-mode (M-mode) then it MUST
    /// configure PMP and other M-mode state before transferring control to supervisor-mode software.
    ///
    /// The `hartid` parameter specifies the target hart which is to be started.
    ///
    /// The `start_addr` parameter points to a runtime-specified physical address, where the hart can start executing
    /// in supervisor-mode.
    ///
    /// The `value` parameter is a XLEN-bit value which will be set in the a1 register when the hart starts executing at
    /// `start_addr`.
    pub fn hartStart(
        hartid: usize,
        start_addr: usize,
        value: usize,
    ) HartStartError!void {
        if (runtime_safety) {
            ecall.threeArgsNoReturnWithError(
                .HSM,
                @intFromEnum(HSM_FID.HART_START),
                @bitCast(hartid),
                @bitCast(start_addr),
                @bitCast(value),
                HartStartError || error{NotSupported},
            ) catch |err| switch (err) {
                error.NotSupported => unreachable,
                else => |e| return e,
            };
            return;
        }

        return ecall.threeArgsNoReturnWithError(
            .HSM,
            @intFromEnum(HSM_FID.HART_START),
            @bitCast(hartid),
            @bitCast(start_addr),
            @bitCast(value),
            HartStartError,
        );
    }

    pub const HartStopError = error{Failed};

    /// Request the SBI implementation to stop executing the calling hart in supervisor-mode and return it’s ownership
    /// to the SBI implementation.
    ///
    /// This call is not expected to return under normal conditions.
    ///
    /// `hartStop` must be called with the supervisor-mode interrupts disabled.
    pub fn hartStop() HartStopError!noreturn {
        if (runtime_safety) {
            ecall.zeroArgsNoReturnWithError(
                .HSM,
                @intFromEnum(HSM_FID.HART_STOP),
                HartStopError || error{NotSupported},
            ) catch |err| switch (err) {
                error.NotSupported => unreachable,
                else => |e| return e,
            };
        } else {
            try ecall.zeroArgsNoReturnWithError(
                .HSM,
                @intFromEnum(HSM_FID.HART_STOP),
                HartStopError,
            );
        }
        unreachable;
    }

    pub const HartStatusError = error{InvalidParameter};

    /// Get the current status (or HSM state id) of the given hart
    ///
    /// The harts may transition HSM states at any time due to any concurrent `hartStart`, `hartStop` or `hartSuspend`
    /// calls the return value from this function may not represent the actual state of the hart at the time of return
    /// value verification.
    pub fn hartStatus(hartid: usize) HartStatusError!State {
        if (runtime_safety) {
            return @enumFromInt(ecall.oneArgsWithReturnWithError(
                .HSM,
                @intFromEnum(HSM_FID.HART_GET_STATUS),
                @bitCast(hartid),
                HartStatusError || error{NotSupported},
            ) catch |err| switch (err) {
                error.NotSupported => unreachable,
                else => |e| return e,
            });
        }

        return @enumFromInt(try ecall.oneArgsWithReturnWithError(
            .HSM,
            @intFromEnum(HSM_FID.HART_GET_STATUS),
            @bitCast(hartid),
            HartStatusError,
        ));
    }

    pub const HartSuspendError = error{ NotSupported, InvalidParameter, InvalidAddress, Failed };

    /// Request the SBI implementation to put the calling hart in a platform specific suspend (or low power) state
    /// specified by the `suspend_type` parameter.
    ///
    /// The hart will automatically come out of suspended state and resume normal execution when it receives an
    /// interrupt or platform specific hardware event.
    ///
    /// The platform specific suspend states for a hart can be either retentive or non-retentive in nature. A retentive
    /// suspend state will preserve hart register and CSR values for all privilege modes whereas a non-retentive suspend
    /// state will not preserve hart register and CSR values.
    ///
    /// Resuming from a retentive suspend state is straight forward and the supervisor-mode software will see SBI
    /// suspend call return without any failures.
    ///
    /// The `resume_addr` parameter is unused during retentive suspend.
    ///
    /// Resuming from a non-retentive suspend state is relatively more involved and requires software to restore various
    /// hart registers and CSRs for all privilege modes. Upon resuming from non-retentive suspend state, the hart will
    /// jump to supervisor-mode at address specified by `resume_addr` with specific registers values described
    /// in the SBI Specification
    ///
    /// The `resume_addr` parameter points to a runtime-specified physical address, where the hart can resume execution
    /// in supervisor-mode after a non-retentive suspend.
    ///
    /// The `value` parameter is a XLEN-bit value which will be set in the a1 register when the hart resumes execution
    /// at `resume_addr` after a non-retentive suspend.
    pub fn hartSuspend(
        suspend_type: SuspendType,
        resume_addr: usize,
        value: usize,
    ) HartSuspendError!void {
        return ecall.threeArgsNoReturnWithError(
            .HSM,
            @intFromEnum(HSM_FID.HART_SUSPEND),
            @intCast(@intFromEnum(suspend_type)),
            @bitCast(resume_addr),
            @bitCast(value),
            HartSuspendError,
        );
    }

    pub const SuspendType = enum(u32) {
        /// Default retentive suspend
        retentive = 0,

        /// Default non-retentive suspend
        non_retentive = 0x80000000,

        _,
    };

    pub const State = enum(isize) {
        /// The hart is physically powered-up and executing normally.
        started = 0x0,

        /// The hart is not executing in supervisor-mode or any lower privilege mode.
        ///
        /// It is probably powered-down by the SBI implementation if the underlying platform has a mechanism to
        /// physically power-down harts.
        stopped = 0x1,

        /// Some other hart has requested to start (or power-up) the hart from the `stopped` state and the SBI
        /// implementation is still working to get the hart in the `started` state.
        start_pending = 0x2,

        /// The hart has requested to stop (or power-down) itself from the `started` state and the SBI implementation is
        /// still working to get the hart in the `stopped` state.
        stop_pending = 0x3,

        /// This hart is in a platform specific suspend (or low power) state.
        suspended = 0x4,

        /// The hart has requested to put itself in a platform specific low power state from the `started` state and the
        /// SBI implementation is still working to get the hart in the platform specific `suspended` state.
        suspend_pending = 0x5,

        /// An interrupt or platform specific hardware event has caused the hart to resume normal execution from the
        /// `suspended` state and the SBI implementation is still working to get the hart in the `started` state.
        resume_pending = 0x6,
    };

    const HSM_FID = enum(i32) {
        HART_START = 0x0,
        HART_STOP = 0x1,
        HART_GET_STATUS = 0x2,
        HART_SUSPEND = 0x3,
    };
};

/// The System Reset Extension provides a function that allow the supervisor software to request system-level reboot or
/// shutdown.
///
/// The term "system" refers to the world-view of supervisor software and the underlying SBI implementation could be
/// machine mode firmware or hypervisor.
pub const reset = struct {
    pub fn available() bool {
        return base.probeExtension(.SRST);
    }

    pub const SystemResetError = error{ NotSupported, InvalidParameter, Failed };

    /// Reset the system based on provided `reset_type` and `reset_reason`.
    ///
    /// This is a synchronous call and does not return if it succeeds.
    ///
    /// When supervisor software is running natively, the SBI implementation is machine mode firmware.
    /// In this case, shutdown is equivalent to physical power down of the entire system and cold reboot is equivalent
    /// to physical power cycle of the entire system.
    /// Further, warm reboot is equivalent to a power cycle of main processor and parts of the system but not the entire
    /// system. For example, on a server class system with a BMC (board management controller), a warm reboot will not
    /// power cycle the BMC whereas a cold reboot will definitely power cycle the BMC.
    ///
    /// When supervisor software is running inside a virtual machine, the SBI implementation is a hypervisor.
    /// The shutdown, cold reboot and warm reboot will behave functionally the same as the native case but might not
    /// result in any physical power changes.
    pub fn systemReset(
        reset_type: ResetType,
        reset_reason: ResetReason,
    ) SystemResetError!noreturn {
        try ecall.twoArgsNoReturnWithError(
            .SRST,
            @intFromEnum(SRST_FID.RESET),
            @intCast(@intFromEnum(reset_type)),
            @intCast(@intFromEnum(reset_reason)),
            SystemResetError,
        );
        unreachable;
    }

    pub const ResetType = enum(u32) {
        shutdown = 0x0,
        cold_reboot = 0x1,
        warm_reboot = 0x2,
        _,
    };

    pub const ResetReason = enum(u32) {
        none = 0x0,
        sysfail = 0x1,
        _,
    };

    const SRST_FID = enum(i32) {
        RESET = 0x0,
    };
};

pub const pmu = struct {
    pub fn available() bool {
        return base.probeExtension(.PMU);
    }

    /// Returns the number of counters (both hardware and firmware)
    pub fn getNumberOfCounters() usize {
        if (runtime_safety) {
            return @bitCast(ecall.zeroArgsWithReturnWithError(
                .PMU,
                @intFromEnum(PMU_FID.NUM_COUNTERS),
                error{NotSupported},
            ) catch unreachable);
        }

        return @bitCast(ecall.zeroArgsWithReturnNoError(.PMU, @intFromEnum(PMU_FID.NUM_COUNTERS)));
    }

    pub const GetCounterInfoError = error{InvalidParameter};

    /// Get details about the specified counter such as underlying CSR number, width of the counter, type of counter
    /// hardware/firmware, etc.
    pub fn getCounterInfo(counter_index: usize) GetCounterInfoError!CounterInfo {
        if (runtime_safety) {
            return @bitCast(ecall.oneArgsWithReturnWithError(
                .PMU,
                @intFromEnum(PMU_FID.COUNTER_GET_INFO),
                @bitCast(counter_index),
                GetCounterInfoError || error{NotSupported},
            ) catch |err| switch (err) {
                error.NotSupported => unreachable,
                else => |e| return e,
            });
        }

        return @bitCast(try ecall.oneArgsWithReturnWithError(
            .PMU,
            @intFromEnum(PMU_FID.COUNTER_GET_INFO),
            @bitCast(counter_index),
            GetCounterInfoError,
        ));
    }

    pub const ConfigureMatchingCounterError = error{ NotSupported, InvalidParameter };

    /// Find and configure a counter from a set of counters which is not started (or enabled) and can monitor the
    /// specified event.
    pub fn configureMatchingCounter(
        counter_base: usize,
        counter_mask: usize,
        config_flags: ConfigFlags,
        event: Event,
    ) ConfigureMatchingCounterError!usize {
        const event_data = event.toEventData();

        return @bitCast(try ecall.fiveArgsLastArg64WithReturnWithError(
            .PMU,
            @intFromEnum(PMU_FID.COUNTER_CFG_MATCH),
            @bitCast(counter_base),
            @bitCast(counter_mask),
            @bitCast(config_flags),
            @bitCast(event_data.event_index),
            event_data.event_data,
            ConfigureMatchingCounterError,
        ));
    }

    pub const StartCountersError = error{ InvalidParameter, AlreadyStarted };

    /// Start or enable a set of counters on the calling HART with the specified initial value.
    ///
    /// The `counter_mask` parameter represent the set of counters whereas the `initial_value` parameter specifies the
    /// initial value of the counter (if `start_flags.init_value` is set).
    pub fn startCounters(
        counter_base: usize,
        counter_mask: usize,
        start_flags: StartFlags,
        initial_value: u64,
    ) StartCountersError!void {
        if (runtime_safety) {
            ecall.fourArgsLastArg64NoReturnWithError(
                .PMU,
                @intFromEnum(PMU_FID.COUNTER_START),
                @bitCast(counter_base),
                @bitCast(counter_mask),
                @bitCast(start_flags),
                initial_value,
                StartCountersError || error{NotSupported},
            ) catch |err| switch (err) {
                error.NotSupported => unreachable,
                else => |e| return e,
            };

            return;
        }

        return ecall.fourArgsLastArg64NoReturnWithError(
            .PMU,
            @intFromEnum(PMU_FID.COUNTER_START),
            @bitCast(counter_base),
            @bitCast(counter_mask),
            @bitCast(start_flags),
            initial_value,
            StartCountersError,
        );
    }

    pub const StopCountersError = error{ InvalidParameter, AlreadyStopped };

    /// Stop or disable a set of counters on the calling HART.
    ///
    /// The `counter_mask` parameter represent the set of counters.
    pub fn stopCounters(
        counter_base: usize,
        counter_mask: usize,
        stop_flags: StopFlags,
    ) StopCountersError!void {
        if (runtime_safety) {
            ecall.threeArgsNoReturnWithError(
                .PMU,
                @intFromEnum(PMU_FID.COUNTER_START),
                @bitCast(counter_base),
                @bitCast(counter_mask),
                @bitCast(stop_flags),
                StopCountersError || error{NotSupported},
            ) catch |err| switch (err) {
                error.NotSupported => unreachable,
                else => |e| return e,
            };

            return;
        }

        return ecall.threeArgsNoReturnWithError(
            .PMU,
            @intFromEnum(PMU_FID.COUNTER_START),
            @bitCast(counter_base),
            @bitCast(counter_mask),
            @bitCast(stop_flags),
            StopCountersError,
        );
    }

    pub const ReadFirmwareCounterError = error{InvalidParameter};

    /// Provide the current value of a firmware counter.
    pub fn readFirmwareCounter(counter_index: usize) ReadFirmwareCounterError!usize {
        if (runtime_safety) {
            return @bitCast(ecall.oneArgsWithReturnWithError(
                .PMU,
                @intFromEnum(PMU_FID.COUNTER_FW_READ),
                @bitCast(counter_index),
                ReadFirmwareCounterError || error{NotSupported},
            ) catch |err| switch (err) {
                error.NotSupported => unreachable,
                else => |e| return e,
            });
        }

        return @bitCast(try ecall.oneArgsWithReturnWithError(
            .PMU,
            @intFromEnum(PMU_FID.COUNTER_FW_READ),
            @bitCast(counter_index),
            ReadFirmwareCounterError,
        ));
    }

    pub const Event = union(EventType) {
        hw: HwEvent,
        hw_cache: HwCacheEvent,
        hw_raw: if (is_64) u48 else u32,
        fw: FwEvent,

        pub const EventType = enum(u4) {
            hw = 0x0,
            hw_cache = 0x1,
            hw_raw = 0x2,
            fw = 0xf,
        };

        pub const HwEvent = enum(u16) {
            /// Event for each CPU cycle
            cpu_cycles = 1,
            /// Event for each completed instruction
            instructions = 2,
            /// Event for cache hit
            cache_references = 3,
            /// Event for cache miss
            cache_misses = 4,
            /// Event for a branch instruction
            branch_instructions = 5,
            /// Event for a branch misprediction
            branch_misses = 6,
            /// Event for each BUS cycle
            bus_cycles = 7,
            /// Event for a stalled cycle in microarchitecture frontend
            stalled_cycles_frontend = 8,
            /// Event for a stalled cycle in microarchitecture backend
            stalled_cycles_backend = 9,
            /// Event for each reference CPU cycle
            ref_cpu_cycles = 10,

            _,
        };

        pub const HwCacheEvent = packed struct(u16) {
            result_id: ResultId,
            op_id: OpId,
            cache_id: CacheId,

            pub const ResultId = enum(u1) {
                access = 0,
                miss = 1,
            };

            pub const OpId = enum(u2) {
                read = 0,
                write = 1,
                prefetch = 2,
            };

            pub const CacheId = enum(u13) {
                /// Level1 data cache event
                l1d = 0,
                /// Level1 instruction cache event
                l1i = 1,
                /// Last level cache event
                ll = 2,
                /// Data TLB event
                dtlb = 3,
                /// Instruction TLB event
                itlb = 4,
                /// Branch predictor unit event
                bpu = 5,
                /// NUMA node cache event
                node = 6,
            };
        };

        pub const FwEvent = enum(u16) {
            misaligned_load = 0,
            misaligned_store = 1,
            access_load = 2,
            access_store = 3,
            illegal_insn = 4,
            set_timer = 5,
            ipi_sent = 6,
            ipi_recvd = 7,
            fence_i_sent = 8,
            fence_i_recvd = 9,
            sfence_vma_sent = 10,
            sfence_vma_rcvd = 11,
            sfence_vma_asid_sent = 12,
            sfence_vma_asid_rcvd = 13,
            hfence_gvma_sent = 14,
            hfence_gvma_rcvd = 15,
            hfence_gvma_vmid_sent = 16,
            hfence_gvma_vmid_rcvd = 17,
            hfence_vvma_sent = 18,
            hfence_vvma_rcvd = 19,
            hfence_vvma_asid_sent = 20,
            hfence_vvma_asid_rcvd = 21,

            _,
        };

        fn toEventData(self: Event) EventData {
            return switch (self) {
                .hw => |hw| EventData{
                    .event_index = @as(u20, @intFromEnum(hw)) | (@as(u20, @intFromEnum(EventType.hw)) << 16),
                    .event_data = 0,
                },
                .hw_cache => |hw_cache| EventData{
                    .event_index = @as(u20, @as(u16, @bitCast(hw_cache))) |
                        (@as(u20, @intFromEnum(EventType.hw_cache)) << 16),
                    .event_data = 0,
                },
                .hw_raw => |hw_raw| EventData{
                    .event_index = @as(u20, @intFromEnum(EventType.hw_raw)) << 16,
                    .event_data = hw_raw,
                },
                .fw => |fw| EventData{
                    .event_index = @as(u20, @intFromEnum(fw)) | (@as(u20, @intFromEnum(EventType.fw)) << 16),
                    .event_data = 0,
                },
            };
        }

        const EventData = struct {
            event_index: usize,
            event_data: u64,
        };
    };

    pub const ConfigFlags = packed struct(usize) {
        /// Skip the counter matching
        skip_match: bool = false,
        /// Clear (or zero) the counter value in counter configuration
        clear_value: bool = false,
        /// Start the counter after configuring a matching counter
        auto_start: bool = false,
        /// Event counting inhibited in VU-mode
        set_vuinh: bool = false,
        /// Event counting inhibited in VS-mode
        set_vsinh: bool = false,
        /// Event counting inhibited in U-mode
        set_uinh: bool = false,
        /// Event counting inhibited in S-mode
        set_sinh: bool = false,
        /// Event counting inhibited in M-mode
        set_minh: bool = false,

        _reserved1: u24 = 0,
        _: if (is_64) u32 else u0 = 0,
    };

    pub const StartFlags = packed struct(usize) {
        /// Set the value of counters based on the `initial_value` parameter
        init_value: bool = false,

        _: if (is_64) u63 else u31 = 0,
    };

    pub const StopFlags = packed struct(usize) {
        /// Reset the counter to event mapping.
        reset: bool = false,

        _: if (is_64) u63 else u31 = 0,
    };

    /// If `type` is `.firmware`, `csr` and `width` should be ignored.
    pub const CounterInfo = packed struct(usize) {
        csr: u12,

        /// Width (One less than number of bits in CSR)
        width: u6,

        _: if (is_64) u45 else u13,

        type: Type,

        pub const Type = enum(u1) {
            hardware = 0,
            firmware = 1,
        };
    };

    const PMU_FID = enum(i32) {
        NUM_COUNTERS = 0x0,
        COUNTER_GET_INFO = 0x1,
        COUNTER_CFG_MATCH = 0x2,
        COUNTER_START = 0x3,
        COUNTER_STOP = 0x4,
        COUNTER_FW_READ = 0x5,
    };
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

/// These legacy SBI extension are deprecated in favor of the other extensions.
///
/// Each function needs to be individually probed to check for support.
pub const legacy = struct {
    pub const ImplementationDefinedError = enum(isize) {
        Success = 0,

        _,
    };

    pub fn setTimerAvailable() bool {
        return base.probeExtension(.LEGACY_SET_TIMER);
    }

    /// Programs the clock for next event after `time_value` time.
    ///
    /// This function also clears the pending timer interrupt bit.
    ///
    /// If the supervisor wishes to clear the timer interrupt without scheduling the next timer event, it can either
    /// request a timer interrupt infinitely far into the future
    /// (i.e., `setTimer(std.math.maxInt(u64))`), or it can instead mask the timer interrupt by clearing `sie.STIE` CSR bit.
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

    pub const ConsoleGetCharError = error{Failed};

    /// Read a byte from debug console.
    pub fn consoleGetChar() ConsoleGetCharError!u8 {
        if (runtime_safety) {
            return @intCast(ecall.legacyZeroArgsWithReturnWithError(
                .LEGACY_CONSOLE_GETCHAR,
                ConsoleGetCharError || error{NotSupported},
            ) catch |err| switch (err) {
                error.NotSupported => unreachable,
                else => |e| return e,
            });
        }

        return @intCast(try ecall.legacyZeroArgsWithReturnWithError(
            .LEGACY_CONSOLE_GETCHAR,
            ConsoleGetCharError,
        ));
    }

    pub fn clearIPIAvailable() bool {
        return base.probeExtension(.LEGACY_CLEAR_IPI);
    }

    /// Clears the pending IPIs if any. The IPI is cleared only in the hart for which this SBI call is invoked.
    ///
    /// `clearIPI` is deprecated because S-mode code can clear `sip.SSIP` CSR bit directly.
    pub fn clearIPI() void {
        if (runtime_safety) {
            ecall.legacyZeroArgsNoReturnWithError(.LEGACY_CLEAR_IPI, error{NotSupported}) catch unreachable;
            return;
        }

        ecall.legacyZeroArgsNoReturnNoError(.LEGACY_CLEAR_IPI);
    }

    pub fn sendIPIAvailable() bool {
        return base.probeExtension(.LEGACY_SEND_IPI);
    }

    /// Send an inter-processor interrupt to all the harts defined in `hart_mask`.
    ///
    /// Interprocessor interrupts manifest at the receiving harts as Supervisor Software Interrupts.
    ///
    /// `hart_mask` is a virtual address that points to a bit-vector of harts. The bit vector is represented as a
    /// sequence of `usize` whose length equals the number of harts in the system divided by the number of bits in a `usize`,
    /// rounded up to the next integer.
    ///
    /// This function returns `ImplementationDefinedError` as an implementation specific error is possible.
    pub fn sendIPI(hart_mask: [*]const usize) ImplementationDefinedError {
        return ecall.legacyOneArgsNoReturnWithRawError(.LEGACY_SEND_IPI, @bitCast(@intFromPtr(hart_mask)));
    }

    pub fn remoteFenceIAvailable() bool {
        return base.probeExtension(.LEGACY_REMOTE_FENCE_I);
    }

    /// Instructs remote harts to execute FENCE.I instruction.
    ///
    /// The `hart_mask` is the same as described in `sendIPI`.
    ///
    /// This function returns `ImplementationDefinedError` as an implementation specific error is possible.
    pub fn remoteFenceI(hart_mask: [*]const usize) ImplementationDefinedError {
        return ecall.legacyOneArgsNoReturnWithRawError(.LEGACY_REMOTE_FENCE_I, @bitCast(@intFromPtr(hart_mask)));
    }

    pub fn remoteSFenceVMAAvailable() bool {
        return base.probeExtension(.LEGACY_REMOTE_SFENCE_VMA);
    }

    /// Instructs the remote harts to execute one or more SFENCE.VMA instructions, covering the range of
    /// virtual addresses between `start` and `size`.
    ///
    /// The `hart_mask` is the same as described in `sendIPI`.
    pub fn remoteSFenceVMA(hart_mask: [*]const usize, start: usize, size: usize) void {
        if (runtime_safety) {
            ecall.legacyThreeArgsNoReturnWithError(
                .LEGACY_REMOTE_SFENCE_VMA,
                @bitCast(@intFromPtr(hart_mask)),
                @bitCast(start),
                @bitCast(size),
                error{NotSupported},
            ) catch unreachable;
            return;
        }

        ecall.legacyThreeArgsNoReturnNoError(
            .LEGACY_REMOTE_SFENCE_VMA,
            @bitCast(@intFromPtr(hart_mask)),
            @bitCast(start),
            @bitCast(size),
        );
    }

    pub fn remoteSFenceVMAWithASIDAvailable() bool {
        return base.probeExtension(.LEGACY_REMOTE_SFENCE_VMA_ASID);
    }

    /// Instruct the remote harts to execute one or more SFENCE.VMA instructions, covering the range of
    /// virtual addresses between `start` and `size`. This covers only the given ASID.
    ///
    /// The `hart_mask` is the same as described in `sendIPI`.
    ///
    /// This function returns `ImplementationDefinedError` as an implementation specific error is possible.
    pub fn remoteSFenceVMAWithASID(hart_mask: [*]const usize, start: usize, size: usize, asid: usize) ImplementationDefinedError {
        return ecall.legacyFourArgsNoReturnWithRawError(
            .LEGACY_REMOTE_SFENCE_VMA_ASID,
            @bitCast(@intFromPtr(hart_mask)),
            @bitCast(start),
            @bitCast(size),
            @bitCast(asid),
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
            ecall.legacyZeroArgsNoReturnWithError(.LEGACY_SHUTDOWN, error{NotSupported}) catch unreachable;
        } else {
            ecall.legacyZeroArgsNoReturnNoError(.LEGACY_SHUTDOWN);
        }
        unreachable;
    }
};

const ecall = struct {
    inline fn zeroArgsNoReturnWithError(eid: EID, fid: i32, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;
        asm volatile ("ecall"
            : [err] "={x10}" (err),
            : [eid] "{x17}" (@intFromEnum(eid)),
              [fid] "{x16}" (fid),
            : "x11"
        );
        if (err == .Success) return;
        return ErrorCode.toError(err, ErrorT);
    }

    inline fn zeroArgsWithReturnWithError(eid: EID, fid: i32, comptime ErrorT: type) ErrorT!isize {
        var err: ErrorCode = undefined;
        var value: isize = undefined;
        asm volatile ("ecall"
            : [err] "={x10}" (err),
              [value] "={x11}" (value),
            : [eid] "{x17}" (@intFromEnum(eid)),
              [fid] "{x16}" (fid),
        );
        if (err == .Success) return value;
        return ErrorCode.toError(err, ErrorT);
    }

    inline fn zeroArgsWithReturnNoError(eid: EID, fid: i32) isize {
        return asm volatile ("ecall"
            : [value] "={x11}" (-> isize),
            : [eid] "{x17}" (@intFromEnum(eid)),
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
            : [eid] "{x17}" (@intFromEnum(eid)),
              [fid] "{x16}" (fid),
              [arg0] "{x10}" (a0),
        );
        if (err == .Success) return value;
        return ErrorCode.toError(err, ErrorT);
    }

    inline fn oneArgsWithReturnNoError(eid: EID, fid: i32, a0: isize) isize {
        return asm volatile ("ecall"
            : [value] "={x11}" (-> isize),
            : [eid] "{x17}" (@intFromEnum(eid)),
              [fid] "{x16}" (fid),
              [arg0] "{x10}" (a0),
            : "x10"
        );
    }

    inline fn oneArgs64NoReturnNoError(eid: EID, fid: i32, a0: u64) void {
        if (is_64) {
            asm volatile ("ecall"
                :
                : [eid] "{x17}" (@intFromEnum(eid)),
                  [fid] "{x16}" (fid),
                  [arg0] "{x10}" (a0),
                : "x11", "x10"
            );
        } else {
            asm volatile ("ecall"
                :
                : [eid] "{x17}" (@intFromEnum(eid)),
                  [fid] "{x16}" (fid),
                  [arg0_lo] "{x10}" (@as(u32, @truncate(a0))),
                  [arg0_hi] "{x11}" (@as(u32, @truncate(a0 >> 32))),
                : "x11", "x10"
            );
        }
    }

    inline fn oneArgs64NoReturnWithError(eid: EID, fid: i32, a0: u64, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;
        if (is_64) {
            asm volatile ("ecall"
                : [err] "={x10}" (err),
                : [eid] "{x17}" (@intFromEnum(eid)),
                  [fid] "{x16}" (fid),
                  [arg0] "{x10}" (a0),
                : "x11"
            );
        } else {
            asm volatile ("ecall"
                : [err] "={x10}" (err),
                : [eid] "{x17}" (@intFromEnum(eid)),
                  [fid] "{x16}" (fid),
                  [arg0_lo] "{x10}" (@as(u32, @truncate(a0))),
                  [arg0_hi] "{x11}" (@as(u32, @truncate(a0 >> 32))),
                : "x11"
            );
        }

        if (err == .Success) return;
        return ErrorCode.toError(err, ErrorT);
    }

    inline fn legacyOneArgs64NoReturnNoError(eid: EID, a0: u64) void {
        if (is_64) {
            asm volatile ("ecall"
                :
                : [eid] "{x17}" (@intFromEnum(eid)),
                  [arg0] "{x10}" (a0),
                : "x10"
            );
        } else {
            asm volatile ("ecall"
                :
                : [eid] "{x17}" (@intFromEnum(eid)),
                  [arg0_lo] "{x10}" (@as(u32, @truncate(a0))),
                  [arg0_hi] "{x11}" (@as(u32, @truncate(a0 >> 32))),
                : "x10"
            );
        }
    }

    inline fn legacyOneArgs64NoReturnWithRawError(eid: EID, a0: u64) legacy.ImplementationDefinedError {
        var err: legacy.ImplementationDefinedError = undefined;

        if (is_64) {
            asm volatile ("ecall"
                : [err] "={x10}" (err),
                : [eid] "{x17}" (@intFromEnum(eid)),
                  [arg0] "{x10}" (a0),
            );
        } else {
            asm volatile ("ecall"
                : [err] "={x10}" (err),
                : [eid] "{x17}" (@intFromEnum(eid)),
                  [arg0_lo] "{x10}" (@as(u32, @truncate(a0))),
                  [arg0_hi] "{x11}" (@as(u32, @truncate(a0 >> 32))),
            );
        }

        return err;
    }

    inline fn legacyOneArgs64NoReturnWithError(eid: EID, a0: u64, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;
        if (is_64) {
            asm volatile ("ecall"
                : [err] "={x10}" (err),
                : [eid] "{x17}" (@intFromEnum(eid)),
                  [arg0] "{x10}" (a0),
            );
        } else {
            asm volatile ("ecall"
                : [err] "={x10}" (err),
                : [eid] "{x17}" (@intFromEnum(eid)),
                  [arg0_lo] "{x10}" (@as(u32, @truncate(a0))),
                  [arg0_hi] "{x11}" (@as(u32, @truncate(a0 >> 32))),
            );
        }

        if (err == .Success) return;
        return ErrorCode.toError(err, ErrorT);
    }

    inline fn legacyOneArgsNoReturnNoError(eid: EID, a0: isize) void {
        asm volatile ("ecall"
            :
            : [eid] "{x17}" (@intFromEnum(eid)),
              [arg0] "{x10}" (a0),
            : "x10"
        );
    }

    inline fn legacyOneArgsNoReturnWithRawError(eid: EID, a0: isize) legacy.ImplementationDefinedError {
        var err: legacy.ImplementationDefinedError = undefined;
        asm volatile ("ecall"
            : [err] "={x10}" (err),
            : [eid] "{x17}" (@intFromEnum(eid)),
              [arg0] "{x10}" (a0),
        );
        return err;
    }

    inline fn legacyOneArgsNoReturnWithError(eid: EID, a0: isize, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;
        asm volatile ("ecall"
            : [err] "={x10}" (err),
            : [eid] "{x17}" (@intFromEnum(eid)),
              [arg0] "{x10}" (a0),
        );
        if (err == .Success) return;
        return ErrorCode.toError(err, ErrorT);
    }

    inline fn legacyThreeArgsNoReturnNoError(eid: EID, a0: isize, a1: isize, a2: isize) void {
        asm volatile ("ecall"
            :
            : [eid] "{x17}" (@intFromEnum(eid)),
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
            : [eid] "{x17}" (@intFromEnum(eid)),
              [arg0] "{x10}" (a0),
              [arg1] "{x11}" (a1),
              [arg2] "{x12}" (a2),
        );

        if (err == .Success) return;
        return ErrorCode.toError(err, ErrorT);
    }

    inline fn legacyFourArgsNoReturnWithRawError(eid: EID, a0: isize, a1: isize, a2: isize, a3: isize) legacy.ImplementationDefinedError {
        var err: legacy.ImplementationDefinedError = undefined;
        asm volatile ("ecall"
            : [err] "={x10}" (err),
            : [eid] "{x17}" (@intFromEnum(eid)),
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
            : [eid] "{x17}" (@intFromEnum(eid)),
              [arg0] "{x10}" (a0),
              [arg1] "{x11}" (a1),
              [arg2] "{x12}" (a2),
              [arg3] "{x13}" (a3),
        );

        if (err == .Success) return;
        return ErrorCode.toError(err, ErrorT);
    }

    inline fn legacyFourArgsNoReturnNoError(eid: EID, a0: isize, a1: isize, a2: isize, a3: isize) void {
        asm volatile ("ecall"
            :
            : [eid] "{x17}" (@intFromEnum(eid)),
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
            : [eid] "{x17}" (@intFromEnum(eid)),
        );
        if (val >= 0) return val;
        return ErrorCode.toError(@enumFromInt(val), ErrorT);
    }

    inline fn legacyZeroArgsNoReturnWithError(eid: EID, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;
        asm volatile ("ecall"
            : [err] "={x10}" (err),
            : [eid] "{x17}" (@intFromEnum(eid)),
        );
        if (err == .Success) return;
        return ErrorCode.toError(err, ErrorT);
    }

    inline fn legacyZeroArgsNoReturnNoError(eid: EID) void {
        asm volatile ("ecall"
            :
            : [eid] "{x17}" (@intFromEnum(eid)),
            : "x10"
        );
    }

    inline fn twoArgsNoReturnWithError(eid: EID, fid: i32, a0: isize, a1: isize, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;
        asm volatile ("ecall"
            : [err] "={x10}" (err),
            : [eid] "{x17}" (@intFromEnum(eid)),
              [fid] "{x16}" (fid),
              [arg0] "{x10}" (a0),
              [arg1] "{x11}" (a1),
            : "x11"
        );
        if (err == .Success) return;
        return ErrorCode.toError(err, ErrorT);
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
                : [eid] "{x17}" (@intFromEnum(eid)),
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
                : [eid] "{x17}" (@intFromEnum(eid)),
                  [fid] "{x16}" (fid),
                  [arg0] "{x10}" (a0),
                  [arg1] "{x11}" (a1),
                  [arg2] "{x12}" (a2),
                  [arg3_lo] "{x13}" (@as(u32, @truncate(a3))),
                  [arg3_hi] "{x14}" (@as(u32, @truncate(a3 >> 32))),
                : "x11"
            );
        }

        if (err == .Success) return;
        return ErrorCode.toError(err, ErrorT);
    }

    inline fn fourArgsNoReturnWithError(eid: EID, fid: i32, a0: isize, a1: isize, a2: isize, a3: isize, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;
        asm volatile ("ecall"
            : [err] "={x10}" (err),
            : [eid] "{x17}" (@intFromEnum(eid)),
              [fid] "{x16}" (fid),
              [arg0] "{x10}" (a0),
              [arg1] "{x11}" (a1),
              [arg2] "{x12}" (a2),
              [arg3] "{x13}" (a3),
            : "x11"
        );
        if (err == .Success) return;
        return ErrorCode.toError(err, ErrorT);
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
                : [eid] "{x17}" (@intFromEnum(eid)),
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
                : [eid] "{x17}" (@intFromEnum(eid)),
                  [fid] "{x16}" (fid),
                  [arg0] "{x10}" (a0),
                  [arg1] "{x11}" (a1),
                  [arg2] "{x12}" (a2),
                  [arg3] "{x13}" (a3),
                  [arg4_lo] "{x14}" (@as(u32, @truncate(a4))),
                  [arg4_hi] "{x15}" (@as(u32, @truncate(a4 >> 32))),
            );
        }

        if (err == .Success) return value;
        return ErrorCode.toError(err, ErrorT);
    }

    inline fn fiveArgsNoReturnWithError(eid: EID, fid: i32, a0: isize, a1: isize, a2: isize, a3: isize, a4: isize, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;
        asm volatile ("ecall"
            : [err] "={x10}" (err),
            : [eid] "{x17}" (@intFromEnum(eid)),
              [fid] "{x16}" (fid),
              [arg0] "{x10}" (a0),
              [arg1] "{x11}" (a1),
              [arg2] "{x12}" (a2),
              [arg3] "{x13}" (a3),
              [arg4] "{x14}" (a4),
            : "x11"
        );
        if (err == .Success) return;
        return ErrorCode.toError(err, ErrorT);
    }

    inline fn threeArgsNoReturnWithError(eid: EID, fid: i32, a0: isize, a1: isize, a2: isize, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;
        asm volatile ("ecall"
            : [err] "={x10}" (err),
            : [eid] "{x17}" (@intFromEnum(eid)),
              [fid] "{x16}" (fid),
              [arg0] "{x10}" (a0),
              [arg1] "{x11}" (a1),
              [arg2] "{x12}" (a2),
            : "x11"
        );
        if (err == .Success) return;
        return ErrorCode.toError(err, ErrorT);
    }

    inline fn threeArgsWithReturnWithError(eid: EID, fid: i32, a0: isize, a1: isize, a2: isize, comptime ErrorT: type) ErrorT!isize {
        var err: ErrorCode = undefined;
        var value: isize = undefined;
        asm volatile ("ecall"
            : [err] "={x10}" (err),
              [value] "={x11}" (value),
            : [eid] "{x17}" (@intFromEnum(eid)),
              [fid] "{x16}" (fid),
              [arg0] "{x10}" (a0),
              [arg1] "{x11}" (a1),
              [arg2] "{x12}" (a2),
        );
        if (err == .Success) return value;
        return ErrorCode.toError(err, ErrorT);
    }
};

const ErrorCode = enum(isize) {
    Success = 0,
    Failed = -1,
    NotSupported = -2,
    InvalidParameter = -3,
    Denied = -4,
    InvalidAddress = -5,
    AlreadyAvailable = -6,
    AlreadyStarted = -7,
    AlreadyStopped = -8,

    inline fn toError(self: ErrorCode, comptime ErrorT: type) ErrorT {
        const errors: []const std.builtin.Type.Error = @typeInfo(ErrorT).error_set.?;
        inline for (errors) |err| {
            if (comptime std.mem.eql(u8, err.name, "Success")) {
                @compileError("Success is not an error");
            }

            if (self == @field(ErrorCode, err.name)) return @field(ErrorT, err.name);
        }
        unreachable;
    }
};

comptime {
    std.testing.refAllDeclsRecursive(@This());
}

const runtime_safety = std.debug.runtime_safety;

const is_64: bool = switch (builtin.cpu.arch) {
    .riscv64 => true,
    .riscv32 => false,
    else => |arch| @compileError("only riscv64 and riscv32 targets supported, found target: " ++ @tagName(arch)),
};

const std = @import("std");
const builtin = @import("builtin");
