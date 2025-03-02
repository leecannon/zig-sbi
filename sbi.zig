// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

/// The base extension is designed to be as small as possible.
///
/// As such, it only contains functionality for probing which SBI extensions are available and for querying the version
/// of the SBI.
///
/// All functions in the base extension must be supported by all SBI implementations.
pub const base = struct {
    /// Returns the current SBI specification version.
    ///
    /// Available from SBI v0.2.
    pub fn getSpecVersion() SpecVersion {
        return @bitCast(ecall.zeroArgsWithReturnNoError(
            .BASE,
            @intFromEnum(BASE_FID.GET_SPEC_VERSION),
        ));
    }

    /// Returns the current SBI implementation ID, which is different for every SBI implementation.
    ///
    /// It is intended that this implementation ID allows software to probe for SBI implementation quirks
    ///
    /// Available from SBI v0.2.
    pub fn getImplementationId() ImplementationId {
        return @enumFromInt(ecall.zeroArgsWithReturnNoError(
            .BASE,
            @intFromEnum(BASE_FID.GET_IMP_ID),
        ));
    }

    /// Returns the current SBI implementation version.
    ///
    /// The encoding of this version number is specific to the SBI implementation.
    ///
    /// Available from SBI v0.2.
    pub fn getImplementationVersion() isize {
        return ecall.zeroArgsWithReturnNoError(
            .BASE,
            @intFromEnum(BASE_FID.GET_IMP_VERSION),
        );
    }

    /// Returns `true` if the given SBI extension ID (EID) is available, or `false` if it is not available.
    ///
    /// Available from SBI v0.2.
    pub fn probeExtension(eid: EID) bool {
        return ecall.oneArgsWithReturnNoError(
            .BASE,
            @intFromEnum(BASE_FID.PROBE_EXT),
            @intFromEnum(eid),
        ) != 0;
    }

    /// Return a value that is legal for the `mvendorid` CSR and 0 is always a legal value for this CSR.
    ///
    /// Available from SBI v0.2.
    pub fn machineVendorId() isize {
        return ecall.zeroArgsWithReturnNoError(
            .BASE,
            @intFromEnum(BASE_FID.GET_MVENDORID),
        );
    }

    /// Return a value that is legal for the `marchid` CSR and 0 is always a legal value for this CSR.
    ///
    /// Available from SBI v0.2.
    pub fn machineArchId() isize {
        return ecall.zeroArgsWithReturnNoError(
            .BASE,
            @intFromEnum(BASE_FID.GET_MARCHID),
        );
    }

    /// Return a value that is legal for the `mimpid` CSR and 0 is always a legal value for this CSR.
    ///
    /// Available from SBI v0.2.
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
        @"Xen Project" = 7,
        @"PolarFire Hart Software Services" = 8,
        coreboot = 9,
        oreboot = 10,
        bhyve = 11,

        _,
    };

    pub const SpecVersion = packed struct(usize) {
        minor: u24,
        major: u7,
        _reserved: u1,
        _: if (is_64) u32 else u0,
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
        DBCN = 0x4442434E,
        SUSP = 0x53555350,
        CPPC = 0x43505043,
        NACL = 0x4E41434C,
        STA = 0x535441,

        _,
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
    /// `stime_value` is in absolute time.
    ///
    /// If the supervisor wishes to clear the timer interrupt without scheduling the next timer event, it may request a
    /// timer interrupt infinitely far into the future (i.e., `setTimer(std.math.maxInt(u64)`).
    ///
    /// Alternatively, to not receive timer interrupts, it may mask timer interrupts by clearing the `sie.STIE` CSR bit.
    ///
    /// This function must clear the pending timer interrupt bit when `time_value` is set to some time in the future,
    /// regardless of whether timer interrupts are masked or not.
    ///
    /// Available from SBI v0.2.
    pub fn setTimer(time_value: u64) void {
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

pub const ipi = struct {
    pub fn available() bool {
        return base.probeExtension(.IPI);
    }

    pub const SendIPIError = error{
        /// Either hart_mask_base or at least one hartid from hart_mask is not valid, i.e., either the hartid is not
        /// enabled by the platform or is not available to the supervisor.
        InvalidParameter,

        /// The request failed for unspecified or unknown other reasons.
        Failed,
    };

    /// Send an inter-processor interrupt to all the harts defined in `hart_mask`.
    ///
    /// Interprocessor interrupts manifest at the receiving harts as supervisor software interrupts.
    ///
    /// Available from SBI v0.2.
    pub fn sendIPI(hart_mask: HartMask) SendIPIError!void {
        const mask, const mask_base = hart_mask.toMaskAndBase();

        return ecall.twoArgsNoReturnWithError(
            .IPI,
            @intFromEnum(IPI_FID.SEND_IPI),
            mask,
            mask_base,
            SendIPIError,
        );
    }

    const IPI_FID = enum(i32) {
        SEND_IPI = 0x0,
    };
};

pub const rfence = struct {
    pub fn available() bool {
        return base.probeExtension(.RFENCE);
    }

    pub const RemoteFenceIError = error{
        /// Either hart_mask_base or at least one hartid from hart_mask is not valid, i.e., either the hartid is not
        /// enabled by the platform or is not available to the supervisor.
        InvalidParameter,

        /// The request failed for unspecified or unknown other reasons.
        Failed,
    };

    /// Instructs remote harts to execute `FENCE.I` instruction.
    ///
    /// Available from SBI v0.2.
    pub fn remoteFenceI(hart_mask: HartMask) RemoteFenceIError!void {
        const mask, const mask_base = hart_mask.toMaskAndBase();

        return ecall.twoArgsNoReturnWithError(
            .RFENCE,
            @intFromEnum(RFENCE_FID.FENCE_I),
            mask,
            mask_base,
            RemoteFenceIError,
        );
    }

    pub const RemoteSFenceVMAError = error{
        /// Either hart_mask_base or at least one hartid from hart_mask is not valid, i.e., either the hartid is not
        /// enabled by the platform or is not available to the supervisor.
        InvalidParameter,

        /// start_addr or size is not valid.
        InvalidAddress,

        /// The request failed for unspecified or unknown other reasons.
        Failed,
    };

    /// Instructs the remote harts to execute one or more `SFENCE.VMA` instructions, covering the range of
    /// virtual addresses between `start_addr` and `start_addr + size`.
    ///
    /// The remote fence operation applies to the entire address space if either:
    ///  - `start_addr` and `size` are both `0`
    ///  - `size` is equal to `2^XLEN-1`
    ///
    /// Available from SBI v0.2.
    pub fn remoteSFenceVMA(
        hart_mask: HartMask,
        start_addr: usize,
        size: usize,
    ) RemoteSFenceVMAError!void {
        const mask, const mask_base = hart_mask.toMaskAndBase();

        return ecall.fourArgsNoReturnWithError(
            .RFENCE,
            @intFromEnum(RFENCE_FID.SFENCE_VMA),
            mask,
            mask_base,
            @bitCast(start_addr),
            @bitCast(size),
            RemoteSFenceVMAError,
        );
    }

    pub const RemoteSFenceVMAWithASIDError = error{
        /// Either asid, hart_mask_base, or at least one hartid from hart_mask is not valid, i.e., either the hartid is
        /// not enabled by the platform or is not available to the supervisor.
        InvalidParameter,

        /// start_addr or size is not valid.
        InvalidAddress,

        /// The request failed for unspecified or unknown other reasons.
        Failed,
    };

    /// Instructs the remote harts to execute one or more `SFENCE.VMA` instructions, covering the range of virtual
    /// addresses between `start_addr` and `start_addr + size`.
    ///
    /// This covers only the given ASID.
    ///
    /// The remote fence operation applies to the entire address space if either:
    ///  - `start_addr` and `size` are both `0`
    ///  - `size` is equal to `2^XLEN-1`
    ///
    /// Available from SBI v0.2.
    pub fn remoteSFenceVMAWithASID(
        hart_mask: HartMask,
        start_addr: usize,
        size: usize,
        asid: usize,
    ) RemoteSFenceVMAWithASIDError!void {
        const mask, const mask_base = hart_mask.toMaskAndBase();

        return ecall.fiveArgsNoReturnWithError(
            .RFENCE,
            @intFromEnum(RFENCE_FID.SFENCE_VMA_ASID),
            mask,
            mask_base,
            @bitCast(start_addr),
            @bitCast(size),
            @bitCast(asid),
            RemoteSFenceVMAWithASIDError,
        );
    }

    pub const RemoteHFenceGVMAWithVMIDError = error{
        /// This function is not supported as it is not implemented or one of the target hart doesn’t support
        /// hypervisor extension.
        NotSupported,

        /// Either vmid, hart_mask_base, or at least one hartid from hart_mask is not valid, i.e., either the hartid is
        /// not enabled by the platform or is not available to the supervisor.
        InvalidParameter,

        /// start_addr or size is not valid.
        InvalidAddress,

        /// The request failed for unspecified or unknown other reasons.
        Failed,
    };

    /// Instruct the remote harts to execute one or more `HFENCE.GVMA` instructions, covering the range of guest physical
    /// addresses between `start_addr` and `start_addr + size` only for the given VMID.
    ///
    /// The remote fence operation applies to the entire address space if either:
    ///  - `start_addr` and `size` are both `0`
    ///  - `size` is equal to `2^XLEN-1`
    ///
    /// This function call is only valid for harts implementing hypervisor extension.
    ///
    /// Available from SBI v0.2.
    pub fn remoteHFenceGVMAWithVMID(
        hart_mask: HartMask,
        start_addr: usize,
        size: usize,
        vmid: usize,
    ) RemoteHFenceGVMAWithVMIDError!void {
        const mask, const mask_base = hart_mask.toMaskAndBase();

        return ecall.fiveArgsNoReturnWithError(
            .RFENCE,
            @intFromEnum(RFENCE_FID.HFENCE_GVMA_VMID),
            mask,
            mask_base,
            @bitCast(start_addr),
            @bitCast(size),
            @bitCast(vmid),
            RemoteHFenceGVMAWithVMIDError,
        );
    }

    pub const RemoteHFenceGVMAError = error{
        /// This function is not supported as it is not implemented or one of the target hart doesn’t support
        /// hypervisor extension.
        NotSupported,

        /// Either hart_mask_base or at least one hartid from hart_mask is not valid, i.e., either the hartid is
        /// not enabled by the platform or is not available to the supervisor.
        InvalidParameter,

        /// start_addr or size is not valid.
        InvalidAddress,

        /// The request failed for unspecified or unknown other reasons.
        Failed,
    };

    /// Instruct the remote harts to execute one or more `HFENCE.GVMA` instructions, covering the range of guest physical
    /// addresses between `start_addr` and `start_addr + size` for all guests.
    ///
    /// The remote fence operation applies to the entire address space if either:
    ///  - `start_addr` and `size` are both `0`
    ///  - `size` is equal to `2^XLEN-1`
    ///
    /// This function call is only valid for harts implementing hypervisor extension.
    ///
    /// Available from SBI v0.2.
    pub fn remoteHFenceGVMA(
        hart_mask: HartMask,
        start_addr: usize,
        size: usize,
    ) RemoteHFenceGVMAError!void {
        const mask, const mask_base = hart_mask.toMaskAndBase();

        return ecall.fourArgsNoReturnWithError(
            .RFENCE,
            @intFromEnum(RFENCE_FID.HFENCE_GVMA),
            mask,
            mask_base,
            @bitCast(start_addr),
            @bitCast(size),
            RemoteHFenceGVMAError,
        );
    }

    pub const RemoteHFenceVVMAWithASIDError = error{
        /// This function is not supported as it is not implemented or one of the target hart doesn’t support
        /// hypervisor extension.
        NotSupported,

        /// Either asid, hart_mask_base, or at least one hartid from hart_mask is not valid, i.e., either the hartid is
        /// not enabled by the platform or is not available to the supervisor.
        InvalidParameter,

        /// start_addr or size is not valid.
        InvalidAddress,

        /// The request failed for unspecified or unknown other reasons.
        Failed,
    };

    /// Instruct the remote harts to execute one or more `HFENCE.VVMA` instructions, covering the range of guest virtual
    /// addresses between `start_addr` and `start_addr + size` for the given ASID and current VMID (in hgatp CSR) of
    /// calling hart.
    ///
    /// The remote fence operation applies to the entire address space if either:
    ///  - `start_addr` and `size` are both `0`
    ///  - `size` is equal to `2^XLEN-1`
    ///
    /// This function call is only valid for harts implementing hypervisor extension.
    ///
    /// Available from SBI v0.2.
    pub fn remoteHFenceVVMAWithASID(
        hart_mask: HartMask,
        start_addr: usize,
        size: usize,
        asid: usize,
    ) RemoteHFenceVVMAWithASIDError!void {
        const mask, const mask_base = hart_mask.toMaskAndBase();

        return ecall.fiveArgsNoReturnWithError(
            .RFENCE,
            @intFromEnum(RFENCE_FID.HFENCE_VVMA_ASID),
            mask,
            mask_base,
            @bitCast(start_addr),
            @bitCast(size),
            @bitCast(asid),
            RemoteHFenceVVMAWithASIDError,
        );
    }

    pub const RemoteHFenceVVMAError = error{
        /// This function is not supported as it is not implemented or one of the target hart doesn’t support
        /// hypervisor extension.
        NotSupported,

        /// Either hart_mask_base or at least one hartid from hart_mask is not valid, i.e., either the hartid is
        /// not enabled by the platform or is not available to the supervisor.
        InvalidParameter,

        /// start_addr or size is not valid.
        InvalidAddress,

        /// The request failed for unspecified or unknown other reasons.
        Failed,
    };

    /// Instruct the remote harts to execute one or more `HFENCE.VVMA` instructions, covering the range of guest virtual
    /// addresses between `start_addr` and `start_addr + size` for current VMID (in hgatp CSR) of calling hart.
    ///
    /// The remote fence operation applies to the entire address space if either:
    ///  - `start_addr` and `size` are both `0`
    ///  - `size` is equal to `2^XLEN-1`
    ///
    /// This function call is only valid for harts implementing hypervisor extension.
    ///
    /// Available from SBI v0.2.
    pub fn remoteHFenceVVMA(
        hart_mask: HartMask,
        start_addr: usize,
        size: usize,
    ) RemoteHFenceVVMAError!void {
        const mask, const mask_base = hart_mask.toMaskAndBase();

        return ecall.fourArgsNoReturnWithError(
            .RFENCE,
            @intFromEnum(RFENCE_FID.HFENCE_VVMA),
            mask,
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
///
/// A platform can have multiple harts grouped into hierarchical topology groups (namely cores, clusters, nodes, etc.)
/// with separate platform specific low-power states for each hierarchical group. These platform specific low-power
/// states of hierarchical topology groups can be represented as platform specific suspend states of a hart.
///
/// An SBI implementation can utilize the suspend states of higher topology groups using one of the following approaches:
/// - Platform-coordinated: In this approach, when a hart becomes idle the supervisor-mode power-management software
/// will request deepest suspend state for the hart and higher topology groups.
/// An SBI implementation should choose a suspend state at higher topology group which is:
///     - Not deeper than the specified suspend state
///     - Wake-up latency is not higher than the wake-up latency of the specified suspend state
///
/// - OS-inititated: In this approach, the supervisor-mode power-managment software will directly request a suspend
/// state for higher topology group after the last hart in that group becomes idle. When a hart becomes idle, the
/// supervisor-mode power-managment software will always select suspend state for the hart itself but it will select a
/// suspend state for a higher topology group only if the hart is the last running hart in the group.
/// An SBI implementation should:
///     - Never choose a suspend state for higher topology group different from the specified suspend state
///     - Always prefer most recent suspend state requested for higher topology group
pub const hsm = struct {
    pub fn available() bool {
        return base.probeExtension(.HSM);
    }

    pub const HartStartError = error{
        /// `start_physical_address` is not valid, possibly due to the following reasons:
        ///  - It is not a valid physical address.
        ///  - Executable access to the address is prohibited by a physical memory protection mechanism or H-extension
        ///    G-stage for supervisor-mode.
        InvalidAddress,

        /// `hartid` is not a valid hartid as the corresponding hart cannot be started in supervisor mode.
        InvalidParameter,

        /// The given hartid is already started.
        AlreadyAvailable,

        /// The start request failed for unspecified or unknown other reasons.
        Failed,
    };

    /// Request the SBI implementation to start executing the target hart in supervisor-mode, at the address specified
    /// by `start_addr`, with register values:
    ///
    /// | Register Name | Register Value         |
    /// | ------------- | ---------------------- |
    /// | `satp`        | `0`                    |
    /// | `sstatus.SIE` | `0`                    |
    /// | `a0`          | `hartid`               |
    /// | `a1`          | `user_value` parameter |
    ///
    /// All other registers are in an undefined state.
    ///
    /// This call is asynchronous — more specifically, `hartStart` may return before the target hart starts executing as
    /// long as the SBI implementation is capable of ensuring the return code is accurate.
    ///
    /// If the SBI implementation is a platform runtime firmware executing in machine-mode (M-mode), then it MUST
    /// configure any physical memory protection it supports, such as that defined by PMP, and other M-mode state,
    /// before transferring control to supervisor-mode software.
    ///
    /// Available from SBI v0.2.
    pub fn hartStart(
        hartid: usize,
        start_physical_address: usize,
        user_value: usize,
    ) HartStartError!void {
        return ecall.threeArgsNoReturnWithError(
            .HSM,
            @intFromEnum(HSM_FID.HART_START),
            @bitCast(hartid),
            @bitCast(start_physical_address),
            @bitCast(user_value),
            HartStartError,
        );
    }

    pub const HartStopError = error{
        /// Failed to stop execution of the current hart.
        Failed,
    };

    /// Request the SBI implementation to stop executing the calling hart in supervisor-mode and return its ownership to
    /// the SBI implementation.
    ///
    /// This call is not expected to return under normal conditions.
    ///
    /// Must be called with supervisor-mode interrupts disabled.
    ///
    /// Available from SBI v0.2.
    pub fn hartStop() HartStopError!noreturn {
        try ecall.zeroArgsNoReturnWithError(
            .HSM,
            @intFromEnum(HSM_FID.HART_STOP),
            HartStopError,
        );
        unreachable;
    }

    pub const HartStatusError = error{
        /// The given hartid is not valid.
        InvalidParameter,
    };

    /// Get the current status (or HSM state id) of the given hart.
    ///
    /// The harts may transition HSM states at any time due to any concurrent `hartStart`, `hartStop` or `hartSuspend`
    /// calls, the return value from this function may not represent the actual state of the hart at the time of return
    /// value verification.
    ///
    /// Available from SBI v0.2.
    pub fn hartStatus(hartid: usize) HartStatusError!State {
        return @enumFromInt(try ecall.oneArgsWithReturnWithError(
            .HSM,
            @intFromEnum(HSM_FID.HART_GET_STATUS),
            @bitCast(hartid),
            HartStatusError,
        ));
    }

    pub const HartSuspendError = error{
        /// `suspend_type` is not reserved and is implemented, but the platform does not support it due to one or more
        /// missing dependencies.
        NotSupported,

        /// `suspend_type` is reserved or is platform-specific and unimplemented.
        InvalidParameter,

        /// `resume_physical_address` is not valid, possibly due to the following reasons:
        ///  - It is not a valid physical address.
        ///  - Executable access to the address is prohibited by a physical memory protection mechanism or H-extension
        ///    G-stage for supervisor-mode.
        InvalidAddress,

        /// The suspend request failed for unspecified or unknown other reasons.
        Failed,
    };

    /// Request the SBI implementation to put the calling hart in a platform specific suspend (or low power) state
    /// specified by the `suspend_type` parameter.
    ///
    /// The hart will automatically come out of suspended state and resume normal execution when it receives an
    /// interrupt or platform specific hardware event.
    ///
    /// The platform specific suspend states for a hart can be either retentive or non-retentive in nature.
    ///
    /// A retentive suspend state will preserve hart register and CSR values for all privilege modes whereas a
    /// non-retentive suspend state will not preserve hart register and CSR values.
    ///
    /// Resuming from a retentive suspend state is straight forward and the supervisor-mode software will see
    /// `hartSuspend` return without any failures. The `resume_physical_address` parameter is unused during retentive
    /// suspend.
    ///
    /// Resuming from a non-retentive suspend state is relatively more involved and requires software to restore various
    /// hart registers and CSRs for all privilege modes. Upon resuming from non-retentive suspend state, the hart will
    /// jump to supervisor-mode at address specified by `resume_physical_address` with register values:
    ///
    /// | Register Name | Register Value         |
    /// | ------------- | ---------------------- |
    /// | `satp`        | `0`                    |
    /// | `sstatus.SIE` | `0`                    |
    /// | `a0`          | `hartid`               |
    /// | `a1`          | `user_value` parameter |
    ///
    /// All other registers are in an undefined state.
    ///
    /// Available from SBI v0.3.
    pub fn hartSuspend(
        suspend_type: SuspendType,
        resume_physical_address: usize,
        user_value: usize,
    ) HartSuspendError!void {
        return ecall.threeArgsNoReturnWithError(
            .HSM,
            @intFromEnum(HSM_FID.HART_SUSPEND),
            @bitCast(@as(usize, suspend_type.toRaw())),
            @bitCast(resume_physical_address),
            @bitCast(user_value),
            HartSuspendError,
        );
    }

    pub const SuspendType = union(enum) {
        /// Default retentive suspend
        retentive,

        /// Default non-retentive suspend
        non_retentive,

        /// | Value                     | Description                             |
        /// | ------------------------- | --------------------------------------- |
        /// | `0x00000000`              | Default retentive suspend               |
        /// | `0x00000001 - 0x0FFFFFFF` | Reserved for future use                 |
        /// | `0x10000000 - 0x7FFFFFFF` | Platform specific retentive suspend     |
        /// | `0x80000000`              | Default non-retentive suspend           |
        /// | `0x80000001 - 0x8FFFFFFF` | Reserved for future use                 |
        /// | `0x90000000 - 0xFFFFFFFF` | Platform specific non-retentive suspend |
        custom: u32,

        fn toRaw(self: SuspendType) u32 {
            return switch (self) {
                .retentive => 0x00000000,
                .non_retentive => 0x80000000,
                .custom => |custom| custom,
            };
        }
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

        _,
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
/// provided by machine mode firmware or a hypervisor.
pub const reset = struct {
    pub fn available() bool {
        return base.probeExtension(.SRST);
    }

    pub const SystemResetError = error{
        /// `reset_type` is not reserved and is implemented, but the platform does not support it due to one or more
        /// missing dependencies.
        NotSupported,

        /// At least one of `reset_type` or `reset_reason` is reserved or is platform-specific and unimplemented.
        InvalidParameter,

        /// The reset request failed for unspecified or unknown other reasons.
        Failed,
    };

    /// Reset the system based on provided `reset_type` and `reset_reason`.
    ///
    /// This is a synchronous call and does not return if it succeeds.
    ///
    /// When supervisor software is running natively, the SBI implementation is provided by machine mode firmware.
    /// In this case, shutdown is equivalent to a physical power down of the entire system and cold reboot is equivalent
    /// to a physical power cycle of the entire system.
    /// Further, warm reboot is equivalent to a power cycle of the main processor and parts of the system, but not the entire system.
    ///
    /// For example, on a server class system with a BMC (board management controller), a warm reboot will not power
    /// cycle the BMC whereas a cold reboot will definitely power cycle the BMC.
    ///
    /// When supervisor software is running inside a virtual machine, the SBI implementation is provided by a hypervisor.
    /// Shutdown, cold reboot and warm reboot will behave functionally the same as the native case, but might not result
    /// in any physical power changes.
    ///
    /// Available from SBI v0.3.
    pub fn systemReset(
        reset_type: ResetType,
        reset_reason: ResetReason,
    ) SystemResetError!noreturn {
        try ecall.twoArgsNoReturnWithError(
            .SRST,
            @intFromEnum(SRST_FID.RESET),
            @bitCast(@as(usize, reset_type.toRaw())),
            @bitCast(@as(usize, reset_reason.toRaw())),
            SystemResetError,
        );
        unreachable;
    }

    pub const ResetType = union(enum) {
        shutdown,
        cold_reboot,
        warm_reboot,

        /// | Value                     | Description                            |
        /// | ------------------------- | -------------------------------------- |
        /// | `0x00000000`              | Shutdown                               |
        /// | `0x00000001`              | Cold reboot                            |
        /// | `0x00000002`              | Warm reboot                            |
        /// | `0x00000003 - 0xEFFFFFFF` | Reserved for future use                |
        /// | `0xF0000000 - 0xFFFFFFFF` | Vendor or platform specific reset type |
        custom: u32,

        fn toRaw(self: ResetType) u32 {
            return switch (self) {
                .shutdown => 0x00000000,
                .cold_reboot => 0x00000001,
                .warm_reboot => 0x00000002,
                .custom => |custom| custom,
            };
        }
    };

    pub const ResetReason = union(enum) {
        no_reason,
        system_failure,

        /// | Value                     | Description                              |
        /// | ------------------------- | ---------------------------------------- |
        /// | `0x00000000`              | No reason                                |
        /// | `0x00000001`              | System failure                           |
        /// | `0x00000002 - 0xDFFFFFFF` | Reserved for future use                  |
        /// | `0xE0000000 - 0xEFFFFFFF` | SBI implementation specific reset reason |
        /// | `0xF0000000 - 0xFFFFFFFF` | Vendor or platform specific reset reason |
        custom: u32,

        fn toRaw(self: ResetReason) u32 {
            return switch (self) {
                .no_reason => 0x00000000,
                .system_failure => 0x00000001,
                .custom => |custom| custom,
            };
        }
    };

    const SRST_FID = enum(i32) {
        RESET = 0x0,
    };
};

/// The RISC-V hardware performance counters such as `mcycle`, `minstret`, and `mhpmcounterX` CSRs are accessible as
/// read-only from supervisor-mode using `cycle`, `instret`, and `hpmcounterX` CSRs.
///
/// The SBI performance monitoring unit (PMU) extension is an interface for supervisor-mode to configure and use the
/// RISC-V hardware performance counters with assistance from the machine-mode (or hypervisor-mode).
///
/// These hardware performance counters can only be started, stopped, or configured from machine-mode using
/// `mcountinhibit` and `mhpmeventX` CSRs. Due to this, a machine-mode SBI implementation may choose to disallow SBI PMU
/// extension if `mcountinhibit` CSR is not implemented by the RISC-V platform.
///
/// A RISC-V platform generally supports monitoring of various hardware events using a limited number of hardware
/// performance counters which are up to 64 bits wide. In addition, a SBI implementation can also provide firmware
/// performance counters which can monitor firmware events such as numberof misaligned load/store instructions, number
/// of RFENCEs, number of IPIs, etc.
///
/// All firmware counters must have same number of bits and can be up to 64 bits wide.
///
/// The SBI PMU extension provides:
///  - An interface for supervisor-mode software to discover and configure per-hart hardware/firmware counters
///  - A typical perf compatible interface for hardware/firmware performance counters and events
///  - Full access to microarchitecture’s raw event encodings
pub const pmu = struct {
    pub fn available() bool {
        return base.probeExtension(.PMU);
    }

    /// Returns the number of counters (both hardware and firmware).
    ///
    /// Available from SBI v0.3.
    pub fn getNumberOfCounters() usize {
        return @bitCast(ecall.zeroArgsWithReturnNoError(.PMU, @intFromEnum(PMU_FID.NUM_COUNTERS)));
    }

    pub const GetCounterInfoError = error{
        /// `counter_index` points to an invalid counter.
        InvalidParameter,
    };

    /// Get details about the specified counter such as underlying CSR number, width of the counter, type of counter
    /// hardware/firmware, etc.
    ///
    /// Available from SBI v0.3.
    pub fn getCounterInfo(counter_index: usize) GetCounterInfoError!CounterInfo {
        const raw: CounterInfo.Raw = @bitCast(try ecall.oneArgsWithReturnWithError(
            .PMU,
            @intFromEnum(PMU_FID.COUNTER_GET_INFO),
            @bitCast(counter_index),
            GetCounterInfoError,
        ));

        return switch (raw.type) {
            .hardware => .{
                .hardware = .{
                    .csr = raw.csr,
                    .width = raw.width,
                },
            },
            .firmware => .firmware,
        };
    }

    pub const ConfigureMatchingCounterError = error{
        /// none of the counters can monitor the specified event.
        NotSupported,

        /// set of counters has at least one invalid counter.
        InvalidParameter,
    };

    /// Find and configure a counter from a set of counters which is not started (or enabled) and can monitor the
    /// specified event.
    ///
    /// The `counter_mask` parameter represent the set of counters whereas `event` represents the event to be monitored.
    ///
    /// Available from SBI v0.3.
    pub fn configureMatchingCounter(
        counter_mask: CounterMask,
        event: Event,
        config_flags: ConfigFlags,
    ) ConfigureMatchingCounterError!usize {
        const raw = event.toRaw();

        return @bitCast(try ecall.fiveArgsLastArg64WithReturnWithError(
            .PMU,
            @intFromEnum(PMU_FID.COUNTER_CFG_MATCH),
            @bitCast(counter_mask.base),
            @bitCast(counter_mask.mask),
            @bitCast(config_flags),
            @as(u20, @bitCast(raw.event_index)),
            raw.event_data,
            ConfigureMatchingCounterError,
        ));
    }

    pub const StartCountersError = error{
        /// set of counters has at least one invalid counter or the given flag parameter has an undefined bit set.
        InvalidParameter,

        /// set of counters includes at least one counter which is already started.
        AlreadyStarted,

        /// the snapshot shared memory is not available and `start_mode` is `.init_snapshot`.
        NoSharedMemory,
    };

    /// Start or enable a set of counters on the calling hart with the specified initial value.
    ///
    /// The `counter_mask` parameter represents the set of counters.
    ///
    /// Available from SBI v0.3.
    pub fn startCounters(
        counter_mask: CounterMask,
        start_mode: StartMode,
    ) StartCountersError!void {
        return ecall.fourArgsLastArg64NoReturnWithError(
            .PMU,
            @intFromEnum(PMU_FID.COUNTER_START),
            @bitCast(counter_mask.base),
            @bitCast(counter_mask.mask),
            @bitCast(start_mode.toRaw()),
            start_mode.initialValue(),
            StartCountersError,
        );
    }

    pub const StopCountersError = error{
        InvalidParameter,
        AlreadyStopped,
    };

    /// Stop or disable a set of counters on the calling hart.
    ///
    /// The `counter_mask` parameter represent the set of counters.
    ///
    /// Available from SBI v0.3.
    pub fn stopCounters(
        counter_mask: CounterMask,
        stop_flags: StopFlags,
    ) StopCountersError!void {
        return ecall.threeArgsNoReturnWithError(
            .PMU,
            @intFromEnum(PMU_FID.COUNTER_START),
            @bitCast(counter_mask.base),
            @bitCast(counter_mask.mask),
            @bitCast(stop_flags),
            StopCountersError,
        );
    }

    pub const ReadFirmwareCounterError = error{
        /// `counter_index` points to a hardware counter or an invalid counter.
        InvalidParameter,
    };

    /// Provide the current value of a firmware counter.
    ///
    /// Available from SBI v0.3.
    pub fn readFirmwareCounter(counter_index: usize) ReadFirmwareCounterError!usize {
        return @bitCast(try ecall.oneArgsWithReturnWithError(
            .PMU,
            @intFromEnum(PMU_FID.COUNTER_FW_READ),
            @bitCast(counter_index),
            ReadFirmwareCounterError,
        ));
    }

    /// Provide the upper 32 bits of the current firmware counter value.
    ///
    /// This function always returns zero for RV64 (or higher) systems.
    ///
    /// Available from SBI v2.0.
    pub fn readFirmwareCounterHigh(counter_index: usize) ReadFirmwareCounterError!usize {
        return @bitCast(try ecall.oneArgsWithReturnWithError(
            .PMU,
            @intFromEnum(PMU_FID.COUNTER_FW_READ_HI),
            @bitCast(counter_index),
            ReadFirmwareCounterError,
        ));
    }

    pub const SetSnapshotSharedMemory = error{
        /// The SBI PMU snapshot functionality is not available in the SBI implementation.
        NotSupported,

        /// The `flags` parameter is not zero or the `shared_memory.set.physical_low` parameter is not 4096 bytes aligned.
        InvalidParameter,

        /// The shared memory is not writable or does not satisfy other requirements.
        InvalidAddress,

        /// The request failed for unspecified or unknown other reasons.
        Failed,
    };

    /// Set and enable or clear and disable the PMU snapshot shared memory on the calling hart.
    ///
    /// This is an optional function and the SBI implementation may choose not to implement it.
    ///
    /// The layout of the snapshot shared memory is:
    ///
    /// | Name                      | Offset | Size | Description |
    /// | ------------------------- | ------ | ---- | ----------- |
    /// | `counter_overflow_bitmap` | 0x0000 | 8    | A bitmap of all logical overflown counters relative to the
    /// |                           |        |      | `counter_mask.base`. This is valid only if the `Sscofpmf` ISA
    /// |                           |        |      | extension is available. Otherwise, it must be zero.
    /// | `counter_values`          | 0x0008 | 512  | An array of 64-bit logical counters where each index represents
    /// |                           |        |      | the value of each logical counter associated with
    /// |                           |        |      | hardware/firmware relative to the `counter_mask.base`.
    /// | Reserved                  | 0x0208 | 3576 | Reserved for future use
    ///
    /// Any future revisions to this structure should be made in a backward compatible manner and will be associated
    /// with an SBI version.
    ///
    /// The logical counter indicies in the `counter_overflow_bitmap` and `counter_values` array are relative w.r.t to
    /// `counter_mask.base` argument present in the `stopCounters` and `startCounters` functions.
    /// This allows the users to use snapshot feature for more than `XLEN` counters if required.
    ///
    /// This function should be invoked only once per hart at boot time.
    ///
    /// Once configured, the SBI implementation has read/write access to the shared memory when `stopCounters` is
    /// invoked with the `StopFlags.take_snapshot` flag `true`.
    ///
    /// The SBI implementation has read only access when `startCounters` is invoked with the `StartMode.init_snapshot`.
    ///
    /// The SBI implementation must not access this memory any other time.
    ///
    /// Available from SBI v2.0.
    pub fn setSnapshotSharedMemory(
        shared_memory: SnapshotSharedMemory,
        flags: SnapshotFlags,
    ) SetSnapshotSharedMemory!void {
        const physical_address_low, const physical_address_high = shared_memory.toRaw();

        try ecall.threeArgsNoReturnWithError(
            .PMU,
            @intFromEnum(PMU_FID.SNAPSHOT_SET_SHMEM),
            @bitCast(physical_address_low),
            @bitCast(physical_address_high),
            @bitCast(flags),
            SetSnapshotSharedMemory,
        );
    }

    pub const GetEventInfoError = error{
        /// The SBI PMU event info retrieval function is not available in the SBI implementation.
        NotSupported,

        /// The `flags` parameter is not zero or the `shared_memory.physical_address_low` parameter is not 16-bytes
        /// aligned or `event_index` value doesn’t conform with the encodings defined in the specification.
        InvalidParameter,

        /// The shared memory is not writable or does not satisfy other requirements.
        InvalidAddress,

        /// The write failed for unspecified or unknown other reasons.
        Failed,
    };

    /// Get details about any PMU event via shared memory.
    ///
    /// The supervisor software can get event specific information for multiple events in one shot by writing an entry
    /// for each event in the shared memory.
    ///
    /// Each entry in the shared memory must be encoded as per the `EventInfo` structure.
    ///
    /// The SBI implementation MUST NOT touch the shared memory once this call returns as supervisor software may free
    /// the memory at any time.
    ///
    /// Available from SBI v3.0.
    pub fn getEventInfo(shared_memory: EventInfoSharedMemory, flags: EventInfoFlags) GetEventInfoError!void {
        try ecall.fourArgsNoReturnWithError(
            .PMU,
            @intFromEnum(PMU_FID.EVENT_GET_INFO),
            @bitCast(shared_memory.num_entries),
            @bitCast(shared_memory.physical_address_low),
            @bitCast(shared_memory.physical_address_high),
            @bitCast(flags),
            GetEventInfoError,
        );
    }

    pub const EventInfo = packed struct(u128) {
        event_index: Event.Index,

        /// Reserved for the future purpose.
        /// Must be zero.
        _reserved1: u12 = 0,

        /// Indicate `event_index` is supported or not.
        ///
        /// The SBI implmenentation MUST update this entire 32-bit word if valid `event_index` and `event_data`
        /// (if applicable) are specified in the entry.
        supported: bool,

        /// Reserved for the future purpose.
        /// Must be zero.
        _reserved2: u31 = 0,

        /// Valid when `event_index.type` is either `hardware_raw`, `hardware_raw_v2` or`firmware`.
        ///
        /// It describes the `event_data` for the specific event specified in `event_index` if applicable.
        event_data: u64,
    };

    pub const EventInfoSharedMemory = struct {
        /// The size of the share memory must be (`16 * num_entries`) bytes.
        num_entries: usize,

        /// MUST be 16-byte aligned
        physical_address_low: usize,
        physical_address_high: usize,
    };

    pub const EventInfoFlags = packed struct(usize) {
        _: usize = 0,
    };

    pub const SnapshotSharedMemory = union(enum) {
        clear,
        /// The size of the snapshot shared memory must be 4096 bytes.
        set: struct {
            /// Specifies the lower XLEN bits of the snapshot shared memory physical base address.
            ///
            /// MUST be 4096 bytes (i.e. page) aligned
            physical_address_low: usize,
            /// Specifies the upper XLEN bits of the snapshot shared memory physical base address.
            physical_address_high: usize,
        },

        fn toRaw(self: SnapshotSharedMemory) struct { usize, usize } {
            return switch (self) {
                .clear => .{ 0, 0 },
                .set => |set| .{ set.physical_address_low, set.physical_address_high },
            };
        }
    };

    pub const SnapshotFlags = packed struct(usize) {
        _: usize = 0,
    };

    pub const CounterMask = struct {
        base: usize,
        mask: usize,
    };

    pub const Event = union(Type) {
        /// Hardware general events
        hardware: Hardware,

        /// Hardware cache events
        hardware_cache: HardwareCache,

        /// Hardware raw events
        ///
        /// On RISC-V platforms with 32 bits wide `mhpmeventX` CSRs, this is the 32-bit value to to be programmed in the
        /// `mhpmeventX` CSR.
        ///
        /// On RISC-V platforms with 64 bits wide `mhpmeventX` CSRs, this is the 48-bit value to be programmed in the
        /// lower 48-bits of `mhpmeventX` CSR and the SBI implementation shall determine the value to be programmed in
        /// the upper 16 bits of `mhpmeventX` CSR.
        ///
        /// **Deprecated in favor of `hardware_raw_v2`**
        hardware_raw: if (is_64) u48 else u32,

        /// Hardware raw events v2
        ///
        /// On RISC-V platforms with 32 bits wide `mhpmeventX` CSRs, this is the 32-bit value to to be programmed in the
        /// `mhpmeventX` CSR.
        ///
        /// On RISC-V platforms with 64 bits wide `mhpmeventX` CSRs, this is the 58-bit value be programmed in the lower
        /// 58-bits of `mhpmeventX` CSR and the SBI implementation shall determine the value to be programmed in the
        /// upper 6 bits of `mhpmeventX` CSR based on privilege specification definition.
        hardware_raw_v2: if (is_64) u58 else u32,

        /// Firmware events
        firmware: Firmware,

        pub const Type = enum(u4) {
            hardware = 0,
            hardware_cache = 1,
            hardware_raw = 2,
            hardware_raw_v2 = 3,
            firmware = 15,
        };

        const Index = packed struct(u20) {
            code: u16,
            type: Type,
        };

        pub const Hardware = enum(u16) {
            /// Event for each CPU cycle
            ///
            /// Counts CPU clock cycles as counted by the `cycle` CSR.
            /// These may be variable frequency cycles, and are not counted when the CPU clock is halted.
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
            ///
            /// Counts fixed-frequency clock cycles while the CPU clock is not halted.
            /// The fixed-frequency of counting might, for example, be the same frequency at which the `time` CSR counts.
            ref_cpu_cycles = 10,
        };

        pub const HardwareCache = packed struct(u16) {
            result_id: ResultId,
            op_id: OpId,
            cache_id: CacheId,

            pub const ResultId = enum(u1) {
                /// Cache access
                access = 0,

                /// Cache miss
                miss = 1,
            };

            pub const OpId = enum(u2) {
                /// Read cache line
                read = 0,

                /// Write cache line
                write = 1,

                /// Prefetch cache line
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

        pub const Firmware = union(FirmwareType) {
            /// Misaligned load trap event
            misaligned_load,

            /// Misaligned store trap event
            misaligned_store,

            /// Load access trap event
            access_load,

            /// Store access trap event
            access_store,

            /// Illegal instruction trap event
            illegal_instruction,

            /// Set timer event
            set_timer,

            /// Sent IPI to other hart event
            ipi_sent,

            /// Received IPI from other hart event
            ipi_received,

            ///  Sent FENCE.I request to other hart event
            fence_i_sent,

            /// Received FENCE.I request from other hart event
            fence_i_received,

            /// Sent SFENCE.VMA request to other hart event
            sfence_vma_sent,

            /// Received SFENCE.VMA request fromother hart event
            sfence_vma_received,

            /// Sent SFENCE.VMA with ASID request to other hart event
            sfence_vma_asid_sent,

            /// Received SFENCE.VMA with ASID request from other hart event
            sfence_vma_asid_received,

            /// Sent HFENCE.GVMA request to other hart event
            hfence_gvma_sent,

            /// Received HFENCE.GVMA request from other hart event
            hfence_gvma_received,

            /// Sent HFENCE.GVMA with VMID request to other hart event
            hfence_gvma_vmid_sent,

            /// Received HFENCE.GVMA with VMID request from other hart event
            hfence_gvma_vmid_received,

            /// Sent HFENCE.VVMA request to other hart event
            hfence_vvma_sent,

            /// Received HFENCE.VVMA request from other hart event
            hfence_vvma_received,

            /// Sent HFENCE.VVMA with ASID request to other hart event
            hfence_vvma_asid_sent,

            /// Received HFENCE.VVMA with ASID request from other hart event
            hfence_vvma_asid_received,

            /// SBI implementation specific firmware events
            ///
            /// Valid values are between 256 and 65534, invalid values will overlap with other events.
            implementation_specific: u16,

            /// RISC-V platform specific firmware events
            platform: u64,

            pub const FirmwareType = enum(u16) {
                misaligned_load = 0,
                misaligned_store = 1,
                access_load = 2,
                access_store = 3,
                illegal_instruction = 4,
                set_timer = 5,
                ipi_sent = 6,
                ipi_received = 7,
                fence_i_sent = 8,
                fence_i_received = 9,
                sfence_vma_sent = 10,
                sfence_vma_received = 11,
                sfence_vma_asid_sent = 12,
                sfence_vma_asid_received = 13,
                hfence_gvma_sent = 14,
                hfence_gvma_received = 15,
                hfence_gvma_vmid_sent = 16,
                hfence_gvma_vmid_received = 17,
                hfence_vvma_sent = 18,
                hfence_vvma_received = 19,
                hfence_vvma_asid_sent = 20,
                hfence_vvma_asid_received = 21,

                implementation_specific = 256,

                platform = 65535,
            };
        };

        fn toRaw(self: Event) Raw {
            return switch (self) {
                .hardware => |hardware| .{
                    .event_index = .{
                        .code = @intFromEnum(hardware),
                        .type = .hardware,
                    },
                    .event_data = 0,
                },
                .hardware_cache => |hardware_cache| .{
                    .event_index = .{
                        .code = @bitCast(hardware_cache),
                        .type = .hardware_cache,
                    },
                    .event_data = 0,
                },
                .hardware_raw => |hardware_raw| .{
                    .event_index = .{
                        .code = 0,
                        .type = .hardware_raw,
                    },
                    .event_data = hardware_raw,
                },
                .hardware_raw_v2 => |hardware_raw_v2| .{
                    .event_index = .{
                        .code = 0,
                        .type = .hardware_raw_v2,
                    },
                    .event_data = hardware_raw_v2,
                },
                .firmware => |firmware| switch (firmware) {
                    .platform => |platform| .{
                        .event_index = .{
                            .code = @intFromEnum(firmware),
                            .type = .firmware,
                        },
                        .event_data = platform,
                    },
                    .implementation_specific => |implementation_specific| .{
                        .event_index = .{
                            .code = implementation_specific,
                            .type = .firmware,
                        },
                        .event_data = 0,
                    },
                    else => .{
                        .event_index = .{
                            .code = @intFromEnum(firmware),
                            .type = .firmware,
                        },
                        .event_data = 0,
                    },
                },
            };
        }

        const Raw = struct {
            event_index: Index,

            _: if (is_64) u44 else u12 = 0,

            event_data: u64,
        };
    };

    pub const ConfigFlags = packed struct(usize) {
        /// Skip the counter matching
        ///
        /// If `true` the SBI implementation will unconditionally select the first counter from the set of counters
        /// specified by the `counter_base` and `counter_mask` parameters.
        skip_match: bool = false,

        /// Clear (or zero) the counter value in counter configuration
        clear_value: bool = false,

        /// Start the counter after configuring a matching counter
        ///
        /// Has no impact on counter value.
        auto_start: bool = false,

        /// Event counting inhibited in VU-mode
        ///
        /// Event filtering hint and can be ignored or overridden by the SBI implementation for security concerns or due
        /// to lack of event filtering support in the underlying RISC-V platform.
        set_vuinh: bool = false,

        /// Event counting inhibited in VS-mode
        ///
        /// Event filtering hint and can be ignored or overridden by the SBI implementation for security concerns or due
        /// to lack of event filtering support in the underlying RISC-V platform.
        set_vsinh: bool = false,

        /// Event counting inhibited in U-mode
        ///
        /// Event filtering hint and can be ignored or overridden by the SBI implementation for security concerns or due
        /// to lack of event filtering support in the underlying RISC-V platform.
        set_uinh: bool = false,

        /// Event counting inhibited in S-mode
        ///
        /// Event filtering hint and can be ignored or overridden by the SBI implementation for security concerns or due
        /// to lack of event filtering support in the underlying RISC-V platform.
        set_sinh: bool = false,

        /// Event counting inhibited in M-mode
        ///
        /// Event filtering hint and can be ignored or overridden by the SBI implementation for security concerns or due
        /// to lack of event filtering support in the underlying RISC-V platform.
        set_minh: bool = false,

        _: if (is_64) u56 else u24 = 0,
    };

    pub const StartMode = union(enum) {
        /// The counter value will not be modified and the event counting will start from the current counter value.
        none,

        /// Set the value of the counters to this value.
        init_value: u64,

        /// Initialize the given counters from shared memory if available.
        ///
        /// The shared memory address must be set during boot via sbi_pmu_snapshot_set_shmem before the this may be used.
        ///
        /// The SBI implementation must initialize all the given valid counters (to be started) from the value set in
        /// the shared snapshot memory.
        init_snapshot,

        fn initialValue(self: StartMode) u64 {
            return switch (self) {
                .init_value => |value| value,
                else => 0,
            };
        }

        fn toRaw(self: StartMode) Raw {
            return switch (self) {
                .none => .{
                    .init_value = false,
                    .init_snapshot = false,
                },
                .init_value => .{
                    .init_value = true,
                    .init_snapshot = false,
                },
                .init_snapshot => .{
                    .init_value = false,
                    .init_snapshot = true,
                },
            };
        }

        const Raw = packed struct(usize) {
            init_value: bool,
            init_snapshot: bool,
            _: if (is_64) u62 else u30 = 0,
        };
    };

    pub const StopFlags = packed struct(usize) {
        /// Reset the counter to event mapping.
        reset: bool = false,

        /// Save a snapshot of the given counter’s values in the shared memory if available.
        ///
        /// The shared memory address must be set during boot via sbi_pmu_snapshot_set_shmem before the this may be used.
        ///
        /// The SBI implementation must save the current value of all the stopped counters in the shared memory if this
        /// is `true`.
        ///
        /// The values corresponding to all other counters must not be modified.
        ///
        /// The SBI implementation must additionally update the overflown counter bitmap in the shared memory.
        take_snapshot: bool = false,

        _: if (is_64) u62 else u30 = 0,
    };

    pub const CounterInfo = union(Type) {
        hardware: Hardware,
        firmware,

        pub const Hardware = struct {
            csr: u12,

            /// Width (One less than number of bits in CSR)
            width: u6,
        };

        pub const Type = enum(u1) {
            hardware = 0,
            firmware = 1,
        };

        const Raw = packed struct(usize) {
            csr: u12,
            width: u6,
            _: if (is_64) u45 else u13,
            type: Type,
        };
    };

    const PMU_FID = enum(i32) {
        NUM_COUNTERS = 0x0,
        COUNTER_GET_INFO = 0x1,
        COUNTER_CFG_MATCH = 0x2,
        COUNTER_START = 0x3,
        COUNTER_STOP = 0x4,
        COUNTER_FW_READ = 0x5,
        COUNTER_FW_READ_HI = 0x6,
        SNAPSHOT_SET_SHMEM = 0x7,
        EVENT_GET_INFO = 0x8,
    };
};

/// The debug console extension defines a generic mechanism for debugging and boot-time early prints from
/// supervisor-mode software.
///
/// This extension replaces the legacy console putchar (EID #0x01) and console getchar (EID #0x02) extensions.
///
/// The debug console extension allows supervisor-mode software to write or read multiple bytes in a single SBI call.
///
/// If the underlying physical console has extra bits for error checking (or correction) then these extra bits should be
/// handled by the SBI implementation.
///
/// Note: It is recommended that bytes sent/received using the debug console extension follow UTF-8 character encoding.
pub const debug_console = struct {
    pub fn available() bool {
        return base.probeExtension(.DBCN);
    }

    pub const WriteError = error{
        /// The memory pointed to by the `num_bytes` and `base_address parameters does not satisfy the requirements.
        InvalidParameter,

        /// Writes to the debug console is not allowed.
        Denied,

        /// Failed to write due to I/O errors.
        Failed,
    };

    /// Write bytes to the debug console from input memory.
    ///
    /// The `num_bytes` parameter specifies the number of bytes in the input memory.
    ///
    /// This is a non-blocking SBI call and it may do partial/no writes if the debug console is not able to accept more
    /// bytes.
    ///
    /// Returns the number of bytes written to the debug console.
    ///
    /// Available from SBI v2.0.
    pub fn write(base_address: BaseAddress, num_bytes: usize) WriteError!usize {
        return @bitCast(try ecall.threeArgsWithReturnWithError(
            .DBCN,
            @intFromEnum(DBCN_FID.CONSOLE_WRITE),
            @bitCast(num_bytes),
            @bitCast(base_address.physical_address_low),
            @bitCast(base_address.physical_address_high),
            WriteError,
        ));
    }

    pub const ReadError = error{
        /// The memory pointed to by the `num_bytes` and `base_address parameters does not satisfy the requirements.
        InvalidParameter,

        /// Reads from the debug console is not allowed.
        Denied,

        /// Failed to read due to I/O errors.
        Failed,
    };

    /// Read bytes from the debug console into an output memory.
    ///
    /// The `num_bytes` parameter specifies the maximum number of bytes which can be written into the output memory.
    ///
    /// This is a non-blocking SBI call and it will not write anything into the output memory if there are no bytes to
    /// be read in the debug console.
    ///
    /// Returns the number of bytes read from the debug console.
    ///
    /// Available from SBI v2.0.
    pub fn read(base_address: BaseAddress, num_bytes: usize) ReadError!usize {
        return @bitCast(try ecall.threeArgsWithReturnWithError(
            .DBCN,
            @intFromEnum(DBCN_FID.CONSOLE_READ),
            @bitCast(num_bytes),
            @bitCast(base_address.physical_address_low),
            @bitCast(base_address.physical_address_high),
            ReadError,
        ));
    }

    pub const WriteByteError = error{
        /// Write to the debug console is not allowed.
        Denied,

        /// Failed to write the byte due to I/O errors.
        Failed,
    };

    /// Write a single byte to the debug console.
    ///
    /// This is a blocking SBI call and it will only return after writing the specified byte to the debug console.
    ///
    /// Available from SBI v2.0.
    pub fn writeByte(byte: u8) WriteByteError!void {
        try ecall.oneArgsNoReturnWithError(
            .DBCN,
            @intFromEnum(DBCN_FID.CONSOLE_WRITE_BYTE),
            byte,
            WriteByteError,
        );
    }

    pub const BaseAddress = struct {
        physical_address_low: usize,
        physical_address_high: usize,
    };

    const DBCN_FID = enum(i32) {
        CONSOLE_WRITE = 0x0,
        CONSOLE_READ = 0x1,
        CONSOLE_WRITE_BYTE = 0x2,
    };
};

/// The system suspend extension defines a set of system-level sleep states and a function which allows the
/// supervisor-mode software to request that the system transitions to a sleep state.
///
/// The term "system" refers to the world-view of the supervisor software domain invoking the call. System suspend may
/// only suspend the part of the overall system which is visible to the invoking supervisor software domain.
///
/// The system suspend extension does not provide any way for supported sleep types to be probed. Platforms are expected
/// to specify their supported system sleep types and per-type wake up devices in their hardware descriptions.
/// The `SleepType.suspend_to_ram` sleep type is the one exception, and its presence is implied by that of the extension.
pub const system_suspend = struct {
    pub fn available() bool {
        return base.probeExtension(.SUSP);
    }

    pub const SystemSuspendError = error{
        /// `sleep_type` is reserved or is platform-specific and unimplemented.
        InvalidParameter,

        /// `sleep_type` is not reserved and is implemented, but the platform does not support it due to one or more
        /// missing dependencies.
        NotSupported,

        /// `resume_physical_address` is not valid, possibly due to the following reasons:
        ///  - It is not a valid physical address.
        ///  - Executable access to the address is prohibited by a physical memory protection mechanism or H-extension
        ///    G-stage for supervisor-mode.
        InvalidAddress,

        /// The suspend request failed due to unsatisfied entry criteria.
        Denied,

        /// The suspend request failed for unspecified or unknown other reasons.
        Failed,
    };

    /// A successful suspend and wake up, results in the hart which initiated the suspend, resuming from the STOPPED
    /// state. To resume, the hart will jump to supervisor-mode, at the address specified by `resume_physical_address`,
    /// with the specific register values:
    ///
    /// | Register Name | Register Value         |
    /// | ------------- | ---------------------- |
    /// | `satp`        | `0`                    |
    /// | `sstatus.SIE` | `0`                    |
    /// | `a0`          | `hartid`               |
    /// | `a1`          | `user_value` parameter |
    ///
    /// All other registers are in an undefined state.
    ///
    /// Besides ensuring all entry criteria for the selected sleep type are met, such as ensuring other harts are in the
    /// STOPPED state, the caller must ensure all power units and domains are in a state compatible with the selected
    /// sleep type.
    ///
    /// The preparation of the power units, power domains, and wake-up devices used for resumption from the system sleep
    /// state is platform specific and beyond the scope of this specification.
    ///
    /// When supervisor software is running inside a virtual machine, the SBI implementation is provided by a hypervisor.
    /// System suspend will behave similarly to the native case from the point of view of the supervisor software.
    ///
    /// Available from SBI v2.0.
    pub fn systemSuspend(
        sleep_type: SleepType,
        resume_physical_address: usize,
        user_value: usize,
    ) SystemSuspendError!noreturn {
        try ecall.threeArgsNoReturnWithError(
            .SUSP,
            @intFromEnum(SUSP_FID.SYSTEM_SUSPEND),
            @bitCast(@as(usize, sleep_type.toRaw())),
            @bitCast(resume_physical_address),
            @bitCast(user_value),
            SystemSuspendError,
        );
        unreachable;
    }

    pub const SleepType = union(enum) {
        suspend_to_ram,

        /// | Value                     | Description                              |
        /// | ------------------------- | ---------------------------------------- |
        /// | `0x00000000`              | This is a “suspend to RAM” sleep type, similar to ACPI’s S2 or S3. Entry
        /// |                           | requires all but the calling hart be in the HSM STOPPED state and all hart
        /// |                           | registers and CSRs are saved to RAM.     |
        /// | `0x00000001 - 0x7fffffff` | Reserved for future use                  |
        /// | `0x80000000 - 0xffffffff` | Platform-specific system sleep types     |
        custom: u32,

        fn toRaw(self: SleepType) u32 {
            return switch (self) {
                .suspend_to_ram => 0x00000000,
                .custom => |custom| custom,
            };
        }
    };

    const SUSP_FID = enum(i32) {
        SYSTEM_SUSPEND = 0x0,
    };
};

/// ACPI defines the Collaborative Processor Performance Control (CPPC) mechanism, which is an abstract and flexible
/// mechanism for the supervisor-mode power-management software to collaborate with an entity in the platform to manage
/// the performance of the processors.
///
/// The SBI CPPC extension provides an abstraction to access the CPPC registers through SBI calls. The CPPC registers
/// can be memory locations shared with a separate platform entity such as a BMC. Even though CPPC is defined in the
/// ACPI specification, it may be possible to implement a CPPC driver based on Device Tree.
pub const cppc = struct {
    pub fn available() bool {
        return base.probeExtension(.CPPC);
    }

    pub const ProbeError = error{
        /// `register` is reserved.
        InvalidParameter,

        /// The probe request failed for unspecified or unknown other reasons.
        Failed,
    };

    /// Probe whether the CPPC register as specified by the `register` parameter is implemented or not by the platform.
    ///
    /// Returns the width of the register in bits if the register is implemented, otherwise returns `null`.
    ///
    /// Available from SBI v2.0.
    pub fn probe(register: Register) ProbeError!?usize {
        const ret = try ecall.oneArgsWithReturnWithError(
            .CPPC,
            @intFromEnum(CPPC_FID.PROBE_REGISTER),
            @bitCast(@as(usize, @intFromEnum(register))),
            ProbeError,
        );
        if (ret == 0) {
            @branchHint(.unlikely);
            return null;
        }
        return @bitCast(ret);
    }

    pub const ReadError = error{
        /// `register` is reserved.
        InvalidParameter,

        /// `register` is not implemented by the platform.
        NotSupported,

        /// `register` is a write-only register.
        Denied,

        /// The read request failed for unspecified or unknown other reasons.
        Failed,
    };

    /// Reads the register as specified in the `register` parameter.
    ///
    /// When supervisor mode XLEN is 32, the  value will only contain the lower 32 bits of the CPPC register value.
    ///
    /// Available from SBI v2.0.
    pub fn read(register: Register) ReadError!usize {
        return @bitCast(try ecall.oneArgsWithReturnWithError(
            .CPPC,
            @intFromEnum(CPPC_FID.READ_REGISTER),
            @bitCast(@as(usize, @intFromEnum(register))),
            ReadError,
        ));
    }

    /// Reads the upper 32-bit value of the register specified in the `register` parameter.
    ///
    /// This function always returns zero in when supervisor mode XLEN is 64 or higher.
    ///
    /// Available from SBI v2.0.
    pub fn readHigh(register: Register) ReadError!usize {
        return @bitCast(try ecall.oneArgsWithReturnWithError(
            .CPPC,
            @intFromEnum(CPPC_FID.READ_HIGH_REGISTER),
            @bitCast(@as(usize, @intFromEnum(register))),
            ReadError,
        ));
    }

    pub const WriteError = error{
        /// `register` is reserved.
        InvalidParameter,

        /// `register` is not implemented by the platform.
        NotSupported,

        /// `register` is a read-only register.
        Denied,

        ///  The write request failed for unspecified or unknown other reasons.
        Failed,
    };

    /// Writes the value passed in the `value` parameter to the register as specified in the `register` parameter.
    ///
    /// Available from SBI v2.0.
    pub fn write(register: Register, value: u64) WriteError!void {
        try ecall.twoArgsLastArg64NoReturnWithError(
            .CPPC,
            @intFromEnum(CPPC_FID.WRITE_REGISTER),
            @bitCast(@as(usize, @intFromEnum(register))),
            value,
            WriteError,
        );
    }

    /// The identifiers for all CPPC registers to be used by the SBI CPPC functions.
    ///
    /// The first half of the 32-bit register space corresponds to the registers as defined by the ACPI specification.
    /// The second half provides the information not defined in the ACPI specification, but is additionally required by
    /// the supervisor-mode power-management software.
    pub const Register = enum(u32) {
        /// Bit width 32 - Attribute Read-only - ACPI Spec 6.5: 8.4.6.1.1.1
        HighestPerformance = 0x00000000,
        /// Bit width 32 - Attribute Read-only - ACPI Spec 6.5: 8.4.6.1.1.2
        NominalPerformance = 0x00000001,
        /// Bit width 32 - Attribute Read-only - ACPI Spec 6.5: 8.4.6.1.1.4
        LowestNonlinearPerformance = 0x00000002,
        /// Bit width 32 - Attribute Read-only - ACPI Spec 6.5: 8.4.6.1.1.5
        LowestPerformance = 0x00000003,
        /// Bit width 32 - Attribute Read-only - ACPI Spec 6.5: 8.4.6.1.1.6
        GuaranteedPerformanceRegister = 0x00000004,
        /// Bit width 32 - Attribute Read/Write - ACPI Spec 6.5: 8.4.6.1.2.3
        DesiredPerformanceRegister = 0x00000005,
        /// Bit width 32 - Attribute Read/Write - ACPI Spec 6.5: 8.4.6.1.2.2
        MinimumPerformanceRegister = 0x00000006,
        /// Bit width 32 - Attribute Read/Write - ACPI Spec 6.5: 8.4.6.1.2.1
        MaximumPerformanceRegister = 0x00000007,
        /// Bit width 32 - Attribute Read/Write - ACPI Spec 6.5: 8.4.6.1.2.4
        PerformanceReductionToleranceRegister = 0x00000008,
        /// Bit width 32 - Attribute Read/Write - ACPI Spec 6.5: 8.4.6.1.2.5
        TimeWindowRegister = 0x00000009,
        /// Bit width 32/64 - Attribute Read-only - ACPI Spec 6.5: 8.4.6.1.3.1
        CounterWraparoundTime = 0x0000000A,
        /// Bit width 32/64 - Attribute Read-only - ACPI Spec 6.5: 8.4.6.1.3.1
        ReferencePerformanceCounterRegister = 0x0000000B,
        /// Bit width 32/64 - Attribute Read-only - ACPI Spec 6.5: 8.4.6.1.3.1
        DeliveredPerformanceCounterRegister = 0x0000000C,
        /// Bit width 32 - Attribute Read/Write - ACPI Spec 6.5: 8.4.6.1.3.2
        PerformanceLimitedRegister = 0x0000000D,
        /// Bit width 32 - Attribute Read/Write - ACPI Spec 6.5: 8.4.6.1.4
        CPPCEnableRegister = 0x0000000E,
        /// Bit width 32 - Attribute Read/Write - ACPI Spec 6.5: 8.4.6.1.5
        AutonomousSelectionEnable = 0x0000000F,
        /// Bit width 32 - Attribute Read/Write - ACPI Spec 6.5: 8.4.6.1.6
        AutonomousActivityWindowRegister = 0x00000010,
        /// Bit width 32 - Attribute Read/Write - ACPI Spec 6.5: 8.4.6.1.7
        EnergyPerformancePreferenceRegister = 0x00000011,
        /// Bit width 32 - Attribute Read-only - ACPI Spec 6.5: 8.4.6.1.1.3
        ReferencePerformance = 0x00000012,
        /// Bit width 32 - Attribute Read-only - ACPI Spec 6.5: 8.4.6.1.1.7
        LowestFrequency = 0x00000013,
        /// Bit width 32 - Attribute Read-only - ACPI Spec 6.5: 8.4.6.1.1.7
        NominalFrequency = 0x00000014,

        // 0x00000015 - 0x7FFFFFFF Reserved for future use

        /// Provides the maximum (worst-case) performance state transition latency in nanoseconds.
        ///
        /// Bit width 32 - Attribute Read-only
        TransitionLatency = 0x80000000,

        // 0x80000001 - 0xFFFFFFFF Reserved for future use
    };

    const CPPC_FID = enum(i32) {
        PROBE_REGISTER = 0x0,
        READ_REGISTER = 0x1,
        READ_HIGH_REGISTER = 0x2,
        WRITE_REGISTER = 0x3,
    };
};

/// Nested virtualization is the ability of a hypervisor to run another hypervisor as a guest. RISC-V nested
/// virtualization requires an L0 hypervisor (running in hypervisor-mode) to trap-and-emulate the RISC-V H-extension
/// functionality (such as CSR accesses, HFENCE instructions, HLV/HSV instructions, etc.) for the L1 hypervisor (running
/// in virtualized supervisor-mode).
///
/// The SBI nested acceleration extension defines a shared memory based interface between the SBI implementation (or L0
/// hypervisor) and the supervisor software (or L1 hypervisor) which allows both to collaboratively reduce traps taken
/// by the L0 hypervisor for emulating RISC-V H-extension functionality.
///
/// The nested acceleration shared memory allows the L1 hypervisor to batch multiple RISC-V H-extension CSR accesses and
/// HFENCE requests which are then emulated by the L0 hypervisor upon an explicit synchronization SBI call.
///
/// This SBI extension defines optional features which MUST be discovered by the supervisor software (or L1 hypervisor)
/// before using the corresponding SBI functions.
///
/// To use the SBI nested acceleration extension, the supervisor software (or L1 hypervisor) MUST set up a nested
/// acceleration shared memory physical address for each virtual hart at boot-time.
/// The physical base address of the nested acceleration shared memory MUST be 4096 bytes (i.e. page) aligned and the
/// size of the nested acceleration shared memory must be `4096 + (1024 * (XLEN / 8))` bytes.
pub const nested_acceleration = struct {
    pub fn available() bool {
        return base.probeExtension(.NACL);
    }

    /// Probe a nested acceleration feature. This is a mandatory function of the SBI nested acceleration extension.
    ///
    /// Available from SBI v2.0.
    pub fn probe(feature_id: FeatureId) bool {
        return ecall.oneArgsWithReturnNoError(
            .NACL,
            @intFromEnum(NACL_FID.PROBE_FEATURE),
            @bitCast(@as(usize, @intFromEnum(feature_id))),
        ) != 0;
    }

    pub const SetSharedMemoryError = error{
        /// The `flags` parameter is not zero or or the `shared_memory.enable.physical_address_low` parameter is not
        /// 4096 bytes aligned.
        InvalidParameter,

        /// The `shared_memory` parameter does not satisfy the requirements
        InvalidAddress,

        ///  The request failed for unspecified or unknown other reasons.
        Failed,
    };

    /// Enable or disable the shared memory for nested acceleration on the calling hart.
    ///
    /// This is a mandatory function of the SBI nested acceleration extension.
    ///
    /// Available from SBI v2.0.
    pub fn setSharedMemory(shared_memory: SharedMemory, flags: SharedMemoryFlags) SetSharedMemoryError!void {
        const physical_address_low, const physical_address_high = shared_memory.toRaw();

        try ecall.threeArgsNoReturnWithError(
            .NACL,
            @intFromEnum(NACL_FID.SET_SHMEM),
            @bitCast(physical_address_low),
            @bitCast(physical_address_high),
            @bitCast(flags),
            SetSharedMemoryError,
        );
    }

    pub const SyncCsrError = error{
        /// The `FeatureId.sync_csr` feature is not available.
        NotSupported,

        /// `csr` is not all-ones bitwise and either:
        /// - `(csr.num & 0x300) != 0x200`
        /// - `csr.num >= 0x1000`
        /// - `csr.num` is not implemented by the SBI implementation
        InvalidParameter,

        /// Nested acceleration shared memory not available.
        NoSharedMemory,
    };

    /// Synchronize CSRs in the nested acceleration shared memory.
    ///
    /// This is an optional function which is only available if the `FeatureId.sync_csr` feature is available.
    ///
    /// The parameter `csr` specifies the set of RISC-V H-extension CSRs to be synchronized.
    ///
    /// Available from SBI v2.0.
    pub fn syncCsr(csr: Csr) SyncCsrError!void {
        try ecall.oneArgsNoReturnWithError(
            .NACL,
            @intFromEnum(NACL_FID.SYNC_CSR),
            @bitCast(csr.toRaw()),
            SyncCsrError,
        );
    }

    pub const SyncHfenceError = error{
        /// `FeatureId.sync_hfence` feature is not available.
        NotSupported,

        /// `entry` is not all-ones bitwise and `entry.index >= (3840 / XLEN)`.
        InvalidParameter,

        /// Nested acceleration shared memory not available.
        NoSharedMemory,
    };

    /// Synchronize HFENCEs in the nested acceleration shared memory.
    ///
    /// This is an optional function which is only available if the `FeatureId.sync_hfence` feature is available.
    ///
    /// The parameter `entry` specifies the set of nested HFENCE entries to be synchronized.
    ///
    /// Available from SBI v2.0.
    fn syncHfence(entry: HfenceEntry) SyncHfenceError!void {
        try ecall.oneArgsNoReturnWithError(
            .NACL,
            @intFromEnum(NACL_FID.SYNC_HFENCE),
            @bitCast(entry.toRaw()),
            SyncHfenceError,
        );
    }

    pub const SyncSretError = error{
        /// `FeatureId.sync_sret` feature is not available.
        NotSupported,

        /// Nested acceleration shared memory not available.
        NoSharedMemory,
    };

    /// Synchronize CSRs and HFENCEs in the nested acceleration shared memory and emulate the SRET instruction.
    ///
    /// This is an optional function which is only available if the `FeatureId.sync_sret` feature is available.
    ///
    /// This function is used by supervisor software (or L1 hypervisor) to do a synchronize SRET request and the SBI
    /// implementation (or L0 hypervisor) MUST handle it as described in the SBI specification section 15.3.
    ///
    /// This function does not return upon success.
    ///
    /// Available from SBI v2.0.
    pub fn syncSret() SyncSretError!noreturn {
        try ecall.zeroArgsNoReturnWithError(
            .NACL,
            @intFromEnum(NACL_FID.SYNC_SRET),
            SyncSretError,
        );
        unreachable;
    }

    pub const HfenceEntry = union(enum) {
        /// All nested HFENCE entries
        all,
        /// Encoding described in SBI specification section 15.2.
        index: usize,

        fn toRaw(self: HfenceEntry) usize {
            return switch (self) {
                .all => std.math.maxInt(usize),
                .index => |index| index,
            };
        }
    };

    pub const Csr = union(enum) {
        /// All RISC-V H-extension CSRs implemented by the SBI implementation (or L0 hypervisor)
        all,
        /// Encoding described in SBI specification section 15.1.
        num: usize,

        fn toRaw(self: Csr) usize {
            return switch (self) {
                .all => std.math.maxInt(usize),
                .num => |num| num,
            };
        }
    };

    pub const SharedMemory = union(enum) {
        disable,
        /// The size of the shared memory must be `4096 + (XLEN * 128)` bytes.
        enable: struct {
            /// MUST be 4096 bytes (i.e. page) aligned
            physical_address_low: usize,
            physical_address_high: usize,
        },

        fn toRaw(self: SharedMemory) struct { usize, usize } {
            return switch (self) {
                .disable => .{ 0, 0 },
                .enable => |enable| .{ enable.physical_address_low, enable.physical_address_high },
            };
        }
    };

    pub const SharedMemoryFlags = packed struct(usize) {
        _: usize = 0,
    };

    pub const FeatureId = enum(u32) {
        /// Synchronize CSR
        sync_csr = 0x00000000,

        /// Synchronize HFENCE
        sync_hfence = 0x00000001,

        /// Synchronize SRET
        sync_sret = 0x00000002,

        /// Autoswap CSR
        autoswap_csr = 0x00000003,

        /// 0x00000004 - 0xFFFFFFFF Reserved for future use
        _,
    };

    const NACL_FID = enum(i32) {
        PROBE_FEATURE = 0x0,
        SET_SHMEM = 0x1,
        SYNC_CSR = 0x2,
        SYNC_HFENCE = 0x3,
        SYNC_SRET = 0x4,
    };
};

/// SBI implementations may encounter situations where virtual harts are ready to run, but must be withheld from running.
/// These situations may be, for example, when multiple SBI domains share processors or when an SBI implementation is a
/// hypervisor and guest contexts share processors with other guest contexts or host tasks.
///
/// When virtual harts are at times withheld from running, observers within the contexts of the virtual harts may need a
/// way to account for less progress than would otherwise be expected. The time a virtual hart was ready, but had to
/// wait, is called "stolen time" and the tracking of it is referred to as steal-time accounting.
///
/// The Steal-time Accounting (STA) extension defines the mechanism in which an SBI implementation provides steal-time
/// and preemption information, for each virtual hart, to supervisor-mode software.
pub const steal_time_accounting = struct {
    pub fn available() bool {
        return base.probeExtension(.STA);
    }

    pub const SetSharedMemoryError = error{
        /// The `flags` parameter is not zero or `shared_memory.phycial_address_low` is not 64-byte aligned.
        InvalidParameter,

        /// The shared memory is not writable or does not satisfy other requirements.
        InvalidAddress,

        /// The request failed for unspecified or unknown other reasons.
        Failed,
    };

    /// Set or disable the shared memory physical base address for steal-time accounting of the calling virtual hart and
    /// enable the SBI implementation’s steal-time information reporting.
    ///
    ///  The SBI implementation MUST zero the first 64 bytes of the shared memory before returning from the SBI call.
    ///
    /// It is not expected for the shared memory to be written by the supervisor-mode software while it is in use for
    /// steal-time accounting. However, the SBI implementation MUST not misbehave if a write from supervisor-mode
    /// software occurs, however, in that case, it MAY leave the shared memory filled with inconsistent data.
    ///
    /// The SBI implementation MUST stop writing to the shared memory when the supervisor-mode software is not runnable,
    /// such as upon system reset or system suspend.
    ///
    /// The layout of shared memory isencoded as per the `StealTimeMemory` structure.
    ///
    /// Available from SBI v2.0.
    pub fn setSharedMemory(shared_memory: SharedMemory, flags: SharedMemoryFlags) SetSharedMemoryError!void {
        const physical_address_low, const physical_address_high = shared_memory.toRaw();

        try ecall.threeArgsNoReturnWithError(
            .STA,
            @intFromEnum(STA_FID.SET_SHMEM),
            @bitCast(physical_address_low),
            @bitCast(physical_address_high),
            @bitCast(flags),
            SetSharedMemoryError,
        );
    }

    pub const StealTimeMemory = extern struct {
        /// The SBI implementation MUST increment this field to an odd value before writing the steal field, and
        /// increment it again to an even value after writing steal (i.e. an odd sequence number indicates an
        /// in-progress update).
        ///
        /// The SBI implementation SHOULD ensure that the sequence field remains odd for only very short periods of time.
        ///
        /// The supervisor-mode software MUST check this field before and after reading the steal field, and repeat the
        /// read if it is different or odd.
        ///
        /// This sequence field enables the value of the steal field to be read by supervisor-mode software executing
        /// in a 32-bit environment.
        sequence: u32,

        /// Always zero.
        ///
        /// Future extensions of the SBI call might allow the supervisor-mode software to write to some of the fields of
        /// the shared memory. Such extensions will not be enabled as long as a zero value is used for the flags
        /// argument to the SBI call.
        flags: u32,

        /// The amount of time in which this virtual hart was not idle and scheduled out, in nanoseconds.
        ///
        /// The time during which the virtual hart is idle will not be reported as steal-time.
        steal: u64,

        /// An advisory flag indicating whether the virtual hart which registered this structure is running or not.
        ///
        /// A non-zero value MAY be written by the SBI implementation if the virtual hart has been preempted (i.e. while
        /// the steal field is increasing), while a zero value MUST be written before the virtual hart starts to run
        /// again.
        ///
        /// This preempted field can, for example, be used by the supervisor-mode software to check if a lock holder has
        /// been preempted, and, in that case, disable optimistic spinning.
        preempted: u8,

        pad: [47]u8,

        comptime {
            std.debug.assert(@sizeOf(StealTimeMemory) == 64);
        }
    };

    pub const SharedMemory = union(enum) {
        disable,
        /// The size of the shared memory must be at least 64 bytes.
        enable: struct {
            /// MUST be 64-byte aligned.
            physical_address_low: usize,
            physical_address_high: usize,
        },

        fn toRaw(self: SharedMemory) struct { usize, usize } {
            return switch (self) {
                .disable => .{ 0, 0 },
                .enable => |enable| .{ enable.physical_address_low, enable.physical_address_high },
            };
        }
    };

    pub const SharedMemoryFlags = packed struct(usize) {
        _: usize = 0,
    };

    const STA_FID = enum(i32) {
        SET_SHMEM = 0x0,
    };
};

pub const HartMask = union(enum) {
    /// all available ids must be considered
    all,
    mask: struct {
        /// a scalar bit-vector containing hartids
        mask: usize,
        /// the starting hartid from which the bit-vector must be computed
        base: usize,
    },

    fn toMaskAndBase(self: HartMask) struct { isize, isize } {
        return switch (self) {
            .all => .{ 0, -1 },
            .mask => |m| .{ @bitCast(m.mask), @bitCast(m.base) },
        };
    }
};

/// These legacy SBI extension are deprecated in favor of the other extensions.
///
/// The page and access faults taken by the SBI implementation while accessing memory on behalf of the supervisor are
/// redirected back to the supervisor with `sepc` CSR pointing to the faulting `ECALL` instruction.
///
/// Each function needs to be individually probed to check for support.
pub const legacy = struct {
    pub fn setTimerAvailable() bool {
        return base.probeExtension(.LEGACY_SET_TIMER);
    }

    /// Programs the clock for next event after `time_value` time.
    ///
    /// This function also clears the pending timer interrupt bit.
    ///
    /// If the supervisor wishes to clear the timer interrupt without scheduling the next timer event, it can either
    /// request a timer interrupt infinitely far into the future (i.e., `setTimer(std.math.maxInt(u64))`), or it can
    /// instead mask the timer interrupt by clearing `sie.STIE` CSR bit.
    ///
    /// Available from SBI v0.1.
    pub fn setTimer(time_value: u64) ImplementationDefinedError {
        return @enumFromInt(ecall.legacyOneArgs64WithReturn(.LEGACY_SET_TIMER, time_value));
    }

    pub fn consolePutCharAvailable() bool {
        return base.probeExtension(.LEGACY_CONSOLE_PUTCHAR);
    }

    /// Write `char` to debug console.
    ///
    /// Unlike `consoleGetChar`, this SBI call will block if there remain any pending characters to be transmitted or if
    /// the receiving terminal is not yet ready to receive the byte. However, if the console doesn’t exist at all, then
    /// the character is thrown away.
    ///
    /// Available from SBI v0.1.
    pub fn consolePutChar(char: u8) ImplementationDefinedError {
        return @enumFromInt(ecall.legacyOneArgsWithReturn(.LEGACY_CONSOLE_PUTCHAR, char));
    }

    pub fn consoleGetCharAvailable() bool {
        return base.probeExtension(.LEGACY_CONSOLE_GETCHAR);
    }

    pub const ConsoleGetCharError = error{Failed};

    /// Read a byte from debug console.
    ///
    /// Available from SBI v0.1.
    pub fn consoleGetChar() ConsoleGetCharError!u8 {
        const ret = ecall.legacyZeroArgsWithReturn(.LEGACY_CONSOLE_GETCHAR);
        if (ret < 0) {
            @branchHint(.unlikely);
            return ConsoleGetCharError.Failed;
        }

        return @intCast(ret);
    }

    pub fn clearIPIAvailable() bool {
        return base.probeExtension(.LEGACY_CLEAR_IPI);
    }

    /// Clears the pending IPIs if any.
    ///
    /// The IPI is cleared only in the hart for which this SBI call is invoked.
    ///
    /// `clearIPI` is deprecated because S-mode code can clear `sip.SSIP` CSR bit directly.
    ///
    /// Returns `true` if an IPI had been pending `false` otherwise.
    ///
    /// Available from SBI v0.1.
    pub fn clearIPI() bool {
        return ecall.legacyZeroArgsWithReturn(.LEGACY_CLEAR_IPI) != 0;
    }

    pub fn sendIPIAvailable() bool {
        return base.probeExtension(.LEGACY_SEND_IPI);
    }

    /// Send an inter-processor interrupt to all the harts defined in `hart_mask`.
    ///
    /// Interprocessor interrupts manifest at the receiving harts as Supervisor Software Interrupts.
    ///
    /// `hart_mask` is a virtual address that points to a bit-vector of harts. The bit vector is represented as a
    /// sequence of `usize` whose length equals the number of harts in the system divided by the number of bits in a
    /// `usize`, rounded up to the next integer.
    ///
    /// Available from SBI v0.1.
    pub fn sendIPI(hart_mask: [*]const usize) ImplementationDefinedError {
        return @enumFromInt(ecall.legacyOneArgsWithReturn(.LEGACY_SEND_IPI, @bitCast(@intFromPtr(hart_mask))));
    }

    pub fn remoteFenceIAvailable() bool {
        return base.probeExtension(.LEGACY_REMOTE_FENCE_I);
    }

    /// Instructs remote harts to execute `FENCE.I` instruction.
    ///
    /// `hart_mask` is a virtual address that points to a bit-vector of harts. The bit vector is represented as a
    /// sequence of `usize` whose length equals the number of harts in the system divided by the number of bits in a
    /// `usize`, rounded up to the next integer.
    ///
    /// Available from SBI v0.1.
    pub fn remoteFenceI(hart_mask: [*]const usize) ImplementationDefinedError {
        return @enumFromInt(ecall.legacyOneArgsWithReturn(.LEGACY_REMOTE_FENCE_I, @bitCast(@intFromPtr(hart_mask))));
    }

    pub fn remoteSFenceVMAAvailable() bool {
        return base.probeExtension(.LEGACY_REMOTE_SFENCE_VMA);
    }

    /// Instructs the remote harts to execute one or more `SFENCE.VMA` instructions, covering the range of
    /// virtual addresses between `start` and `start + size`.
    ///
    /// The remote fence operation applies to the entire address space if either:
    ///  - `start` and `size` are both `0`
    ///  - `size` is equal to `2^XLEN-1`
    ///
    /// `hart_mask` is a virtual address that points to a bit-vector of harts. The bit vector is represented as a
    /// sequence of `usize` whose length equals the number of harts in the system divided by the number of bits in a
    /// `usize`, rounded up to the next integer.
    ///
    /// Available from SBI v0.1.
    pub fn remoteSFenceVMA(hart_mask: [*]const usize, start: usize, size: usize) ImplementationDefinedError {
        return @enumFromInt(ecall.legacyThreeArgsWithReturn(
            .LEGACY_REMOTE_SFENCE_VMA,
            @bitCast(@intFromPtr(hart_mask)),
            @bitCast(start),
            @bitCast(size),
        ));
    }

    pub fn remoteSFenceVMAWithASIDAvailable() bool {
        return base.probeExtension(.LEGACY_REMOTE_SFENCE_VMA_ASID);
    }

    /// Instruct the remote harts to execute one or more `SFENCE.VMA` instructions, covering the range of
    /// virtual addresses between `start` and `start + size`.
    ///
    /// This covers only the given ASID.
    ///
    /// The remote fence operation applies to the entire address space if either:
    ///  - `start` and `size` are both `0`
    ///  - `size` is equal to `2^XLEN-1`
    ///
    /// `hart_mask` is a virtual address that points to a bit-vector of harts. The bit vector is represented as a
    /// sequence of `usize` whose length equals the number of harts in the system divided by the number of bits in a
    /// `usize`, rounded up to the next integer.
    ///
    /// Available from SBI v0.1.
    pub fn remoteSFenceVMAWithASID(hart_mask: [*]const usize, start: usize, size: usize, asid: usize) ImplementationDefinedError {
        return @enumFromInt(ecall.legacyFourArgsWithReturn(
            .LEGACY_REMOTE_SFENCE_VMA_ASID,
            @bitCast(@intFromPtr(hart_mask)),
            @bitCast(start),
            @bitCast(size),
            @bitCast(asid),
        ));
    }

    pub fn systemShutdownAvailable() bool {
        return base.probeExtension(.LEGACY_SHUTDOWN);
    }

    /// Puts all the harts to shutdown state from supervisor point of view.
    ///
    /// This SBI call doesn't return irrespective whether it succeeds or fails.
    ///
    /// Available from SBI v0.1.
    pub fn systemShutdown() noreturn {
        ecall.legacyZeroArgsNoReturn(.LEGACY_SHUTDOWN);
        unreachable;
    }

    pub const ImplementationDefinedError = enum(isize) {
        Success = 0,

        _,
    };
};

const ecall = struct {
    inline fn zeroArgsNoReturnWithError(eid: base.EID, fid: i32, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;
        asm volatile ("ecall"
            : [err] "={a0}" (err),
            : [eid] "{a7}" (@intFromEnum(eid)),
              [fid] "{a6}" (fid),
            : "a1"
        );
        if (err == .Success) {
            @branchHint(.likely);
            return;
        }
        return ErrorCode.toError(err, ErrorT);
    }

    inline fn zeroArgsWithReturnWithError(eid: base.EID, fid: i32, comptime ErrorT: type) ErrorT!isize {
        var err: ErrorCode = undefined;
        var value: isize = undefined;
        asm volatile ("ecall"
            : [err] "={a0}" (err),
              [value] "={a1}" (value),
            : [eid] "{a7}" (@intFromEnum(eid)),
              [fid] "{a6}" (fid),
        );
        if (err == .Success) {
            @branchHint(.likely);
            return value;
        }
        return ErrorCode.toError(err, ErrorT);
    }

    inline fn zeroArgsWithReturnNoError(eid: base.EID, fid: i32) isize {
        return asm volatile ("ecall"
            : [value] "={a1}" (-> isize),
            : [eid] "{a7}" (@intFromEnum(eid)),
              [fid] "{a6}" (fid),
            : "a0"
        );
    }

    inline fn oneArgsNoReturnWithError(eid: base.EID, fid: i32, a0: isize, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;
        asm volatile ("ecall"
            : [err] "={a0}" (err),
            : [eid] "{a7}" (@intFromEnum(eid)),
              [fid] "{a6}" (fid),
              [arg0] "{a0}" (a0),
            : "a1"
        );
        if (err == .Success) {
            @branchHint(.likely);
            return;
        }
        return ErrorCode.toError(err, ErrorT);
    }

    inline fn oneArgsWithReturnWithError(eid: base.EID, fid: i32, a0: isize, comptime ErrorT: type) ErrorT!isize {
        var err: ErrorCode = undefined;
        var value: isize = undefined;
        asm volatile ("ecall"
            : [err] "={a0}" (err),
              [value] "={a1}" (value),
            : [eid] "{a7}" (@intFromEnum(eid)),
              [fid] "{a6}" (fid),
              [arg0] "{a0}" (a0),
        );
        if (err == .Success) {
            @branchHint(.likely);
            return value;
        }
        return ErrorCode.toError(err, ErrorT);
    }

    inline fn oneArgsWithReturnNoError(eid: base.EID, fid: i32, a0: isize) isize {
        return asm volatile ("ecall"
            : [value] "={a1}" (-> isize),
            : [eid] "{a7}" (@intFromEnum(eid)),
              [fid] "{a6}" (fid),
              [arg0] "{a0}" (a0),
            : "a0"
        );
    }

    inline fn oneArgs64NoReturnNoError(eid: base.EID, fid: i32, a0: u64) void {
        if (is_64) {
            asm volatile ("ecall"
                :
                : [eid] "{a7}" (@intFromEnum(eid)),
                  [fid] "{a6}" (fid),
                  [arg0] "{a0}" (a0),
                : "a1", "a0"
            );
        } else {
            asm volatile ("ecall"
                :
                : [eid] "{a7}" (@intFromEnum(eid)),
                  [fid] "{a6}" (fid),
                  [arg0_lo] "{a0}" (@as(u32, @truncate(a0))),
                  [arg0_hi] "{a1}" (@as(u32, @truncate(a0 >> 32))),
                : "a1", "a0"
            );
        }
    }

    inline fn oneArgs64NoReturnWithError(eid: base.EID, fid: i32, a0: u64, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;
        if (is_64) {
            asm volatile ("ecall"
                : [err] "={a0}" (err),
                : [eid] "{a7}" (@intFromEnum(eid)),
                  [fid] "{a6}" (fid),
                  [arg0] "{a0}" (a0),
                : "a1"
            );
        } else {
            asm volatile ("ecall"
                : [err] "={a0}" (err),
                : [eid] "{a7}" (@intFromEnum(eid)),
                  [fid] "{a6}" (fid),
                  [arg0_lo] "{a0}" (@as(u32, @truncate(a0))),
                  [arg0_hi] "{a1}" (@as(u32, @truncate(a0 >> 32))),
                : "a1"
            );
        }

        if (err == .Success) {
            @branchHint(.likely);
            return;
        }
        return ErrorCode.toError(err, ErrorT);
    }

    inline fn twoArgsNoReturnWithError(eid: base.EID, fid: i32, a0: isize, a1: isize, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;
        asm volatile ("ecall"
            : [err] "={a0}" (err),
            : [eid] "{a7}" (@intFromEnum(eid)),
              [fid] "{a6}" (fid),
              [arg0] "{a0}" (a0),
              [arg1] "{a1}" (a1),
            : "a1"
        );
        if (err == .Success) {
            @branchHint(.likely);
            return;
        }
        return ErrorCode.toError(err, ErrorT);
    }

    inline fn twoArgsLastArg64NoReturnWithError(eid: base.EID, fid: i32, a0: isize, a1: u64, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;

        if (is_64) {
            asm volatile ("ecall"
                : [err] "={a0}" (err),
                : [eid] "{a7}" (@intFromEnum(eid)),
                  [fid] "{a6}" (fid),
                  [arg0] "{a0}" (a0),
                  [arg1] "{a1}" (a1),
                : "a1"
            );
        } else {
            asm volatile ("ecall"
                : [err] "={a0}" (err),
                : [eid] "{a7}" (@intFromEnum(eid)),
                  [fid] "{a6}" (fid),
                  [arg0] "{a0}" (a0),
                  [arg1_lo] "{a1}" (@as(u32, @truncate(a1))),
                  [arg1_hi] "{a2}" (@as(u32, @truncate(a1 >> 32))),
                : "a1"
            );
        }

        if (err == .Success) {
            @branchHint(.likely);
            return;
        }
        return ErrorCode.toError(err, ErrorT);
    }

    inline fn fourArgsLastArg64NoReturnWithError(
        eid: base.EID,
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
                : [err] "={a0}" (err),
                : [eid] "{a7}" (@intFromEnum(eid)),
                  [fid] "{a6}" (fid),
                  [arg0] "{a0}" (a0),
                  [arg1] "{a1}" (a1),
                  [arg2] "{a2}" (a2),
                  [arg3] "{a3}" (a3),
                : "a1"
            );
        } else {
            asm volatile ("ecall"
                : [err] "={a0}" (err),
                : [eid] "{a7}" (@intFromEnum(eid)),
                  [fid] "{a6}" (fid),
                  [arg0] "{a0}" (a0),
                  [arg1] "{a1}" (a1),
                  [arg2] "{a2}" (a2),
                  [arg3_lo] "{a3}" (@as(u32, @truncate(a3))),
                  [arg3_hi] "{a4}" (@as(u32, @truncate(a3 >> 32))),
                : "a1"
            );
        }

        if (err == .Success) {
            @branchHint(.likely);
            return;
        }
        return ErrorCode.toError(err, ErrorT);
    }

    inline fn fourArgsNoReturnWithError(eid: base.EID, fid: i32, a0: isize, a1: isize, a2: isize, a3: isize, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;
        asm volatile ("ecall"
            : [err] "={a0}" (err),
            : [eid] "{a7}" (@intFromEnum(eid)),
              [fid] "{a6}" (fid),
              [arg0] "{a0}" (a0),
              [arg1] "{a1}" (a1),
              [arg2] "{a2}" (a2),
              [arg3] "{a3}" (a3),
            : "a1"
        );
        if (err == .Success) {
            @branchHint(.likely);
            return;
        }
        return ErrorCode.toError(err, ErrorT);
    }

    inline fn fiveArgsLastArg64WithReturnWithError(
        eid: base.EID,
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
                : [err] "={a0}" (err),
                  [value] "={a1}" (value),
                : [eid] "{a7}" (@intFromEnum(eid)),
                  [fid] "{a6}" (fid),
                  [arg0] "{a0}" (a0),
                  [arg1] "{a1}" (a1),
                  [arg2] "{a2}" (a2),
                  [arg3] "{a3}" (a3),
                  [arg4] "{a4}" (a4),
            );
        } else {
            asm volatile ("ecall"
                : [err] "={a0}" (err),
                  [value] "={a1}" (value),
                : [eid] "{a7}" (@intFromEnum(eid)),
                  [fid] "{a6}" (fid),
                  [arg0] "{a0}" (a0),
                  [arg1] "{a1}" (a1),
                  [arg2] "{a2}" (a2),
                  [arg3] "{a3}" (a3),
                  [arg4_lo] "{a4}" (@as(u32, @truncate(a4))),
                  [arg4_hi] "{a5}" (@as(u32, @truncate(a4 >> 32))),
            );
        }

        if (err == .Success) {
            @branchHint(.likely);
            return value;
        }
        return ErrorCode.toError(err, ErrorT);
    }

    inline fn fiveArgsNoReturnWithError(eid: base.EID, fid: i32, a0: isize, a1: isize, a2: isize, a3: isize, a4: isize, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;
        asm volatile ("ecall"
            : [err] "={a0}" (err),
            : [eid] "{a7}" (@intFromEnum(eid)),
              [fid] "{a6}" (fid),
              [arg0] "{a0}" (a0),
              [arg1] "{a1}" (a1),
              [arg2] "{a2}" (a2),
              [arg3] "{a3}" (a3),
              [arg4] "{a4}" (a4),
            : "a1"
        );
        if (err == .Success) {
            @branchHint(.likely);
            return;
        }
        return ErrorCode.toError(err, ErrorT);
    }

    inline fn threeArgsNoReturnWithError(eid: base.EID, fid: i32, a0: isize, a1: isize, a2: isize, comptime ErrorT: type) ErrorT!void {
        var err: ErrorCode = undefined;
        asm volatile ("ecall"
            : [err] "={a0}" (err),
            : [eid] "{a7}" (@intFromEnum(eid)),
              [fid] "{a6}" (fid),
              [arg0] "{a0}" (a0),
              [arg1] "{a1}" (a1),
              [arg2] "{a2}" (a2),
            : "a1"
        );
        if (err == .Success) {
            @branchHint(.likely);
            return;
        }
        return ErrorCode.toError(err, ErrorT);
    }

    inline fn threeArgsWithReturnWithError(eid: base.EID, fid: i32, a0: isize, a1: isize, a2: isize, comptime ErrorT: type) ErrorT!isize {
        var err: ErrorCode = undefined;
        var value: isize = undefined;
        asm volatile ("ecall"
            : [err] "={a0}" (err),
              [value] "={a1}" (value),
            : [eid] "{a7}" (@intFromEnum(eid)),
              [fid] "{a6}" (fid),
              [arg0] "{a0}" (a0),
              [arg1] "{a1}" (a1),
              [arg2] "{a2}" (a2),
        );
        if (err == .Success) {
            @branchHint(.likely);
            return value;
        }
        return ErrorCode.toError(err, ErrorT);
    }

    inline fn legacyZeroArgsNoReturn(eid: base.EID) void {
        asm volatile ("ecall"
            :
            : [eid] "{a7}" (@intFromEnum(eid)),
            : "a0"
        );
    }

    inline fn legacyZeroArgsWithReturn(eid: base.EID) isize {
        var val: isize = undefined;

        asm volatile ("ecall"
            : [val] "={a0}" (val),
            : [eid] "{a7}" (@intFromEnum(eid)),
        );

        return val;
    }

    inline fn legacyOneArgsWithReturn(eid: base.EID, a0: isize) isize {
        var val: isize = undefined;

        asm volatile ("ecall"
            : [val] "={a0}" (val),
            : [eid] "{a7}" (@intFromEnum(eid)),
              [arg0] "{a0}" (a0),
        );

        return val;
    }

    inline fn legacyOneArgs64WithReturn(eid: base.EID, a0: u64) isize {
        var val: isize = undefined;

        if (is_64) {
            asm volatile ("ecall"
                : [val] "={a0}" (val),
                : [eid] "{a7}" (@intFromEnum(eid)),
                  [arg0] "{a0}" (a0),
            );
        } else {
            asm volatile ("ecall"
                : [val] "={a0}" (val),
                : [eid] "{a7}" (@intFromEnum(eid)),
                  [arg0_lo] "{a0}" (@as(u32, @truncate(a0))),
                  [arg0_hi] "{a1}" (@as(u32, @truncate(a0 >> 32))),
            );
        }

        return val;
    }

    inline fn legacyThreeArgsWithReturn(eid: base.EID, a0: isize, a1: isize, a2: isize) isize {
        var val: isize = undefined;

        asm volatile ("ecall"
            : [val] "={a0}" (val),
            : [eid] "{a7}" (@intFromEnum(eid)),
              [arg0] "{a0}" (a0),
              [arg1] "{a1}" (a1),
              [arg2] "{a2}" (a2),
        );

        return val;
    }

    inline fn legacyFourArgsWithReturn(eid: base.EID, a0: isize, a1: isize, a2: isize, a3: isize) isize {
        var val: isize = undefined;

        asm volatile ("ecall"
            : [val] "={a0}" (val),
            : [eid] "{a7}" (@intFromEnum(eid)),
              [arg0] "{a0}" (a0),
              [arg1] "{a1}" (a1),
              [arg2] "{a2}" (a2),
              [arg3] "{a3}" (a3),
        );

        return val;
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
    NoSharedMemory = -9,
    InvalidState = -10,
    BadRange = -11,
    Timeout = -12,
    IO = -13,

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

const is_64: bool = switch (builtin.cpu.arch) {
    .riscv64 => true,
    .riscv32 => false,
    else => |arch| @compileError("only riscv64 and riscv32 targets supported, found target: " ++ @tagName(arch)),
};

const std = @import("std");
const builtin = @import("builtin");
