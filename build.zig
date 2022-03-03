const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    b.prominent_compile_errors = true;

    const mode = b.standardReleaseOptions();
    const target = std.zig.CrossTarget{ .cpu_arch = .riscv64 };

    b.enable_qemu = true;

    const tests = b.addTest("sbi.zig");
    tests.setBuildMode(mode);
    tests.setTarget(target);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&tests.step);

    b.default_step = test_step;
}
