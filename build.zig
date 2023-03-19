const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target_32 = std.zig.CrossTarget{ .cpu_arch = .riscv32, .os_tag = .freestanding };
    const target_64 = std.zig.CrossTarget{ .cpu_arch = .riscv64, .os_tag = .freestanding };

    const test_32 = b.addTest(.{
        .name = "test_32",
        .root_source_file = .{ .path = "sbi.zig" },
        .target = target_32,
        .optimize = optimize,
    });

    const test_64 = b.addTest(.{
        .name = "test_64",
        .root_source_file = .{ .path = "sbi.zig" },
        .target = target_64,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&test_64.step);
    test_step.dependOn(&test_32.step);

    b.default_step = test_step;
}
