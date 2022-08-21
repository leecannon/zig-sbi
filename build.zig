const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    b.prominent_compile_errors = true;

    // TODO: https://github.com/ziglang/zig/issues/12554
    b.use_stage1 = true;

    const mode = b.standardReleaseOptions();
    const target_32 = std.zig.CrossTarget{ .cpu_arch = .riscv32, .os_tag = .freestanding };
    const target_64 = std.zig.CrossTarget{ .cpu_arch = .riscv64, .os_tag = .freestanding };

    const test_32 = b.addTestExe("test_32", "sbi.zig");
    test_32.setBuildMode(mode);
    test_32.setTarget(target_32);

    const test_64 = b.addTestExe("test_64", "sbi.zig");
    test_64.setBuildMode(mode);
    test_64.setTarget(target_64);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&test_64.step);
    test_step.dependOn(&test_32.step);

    b.default_step = test_step;
}
