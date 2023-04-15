const std = @import("std");

// TODO: https://github.com/ziglang/zig/issues/15301
const disable_risc32 = true;

pub fn build(b: *std.Build) void {
    const test_step = b.step("test", "Run library tests");

    const optimize = b.standardOptimizeOption(.{});

    const target_64 = std.zig.CrossTarget{ .cpu_arch = .riscv64, .os_tag = .freestanding };

    const test_64 = b.addStaticLibrary(.{
        .name = "test_64",
        .root_source_file = .{ .path = "sbi.zig" },
        .target = target_64,
        .optimize = optimize,
    });
    test_step.dependOn(&test_64.step);

    if (!disable_risc32) {
        const target_32 = std.zig.CrossTarget{ .cpu_arch = .riscv32, .os_tag = .freestanding };

        const test_32 = b.addStaticLibrary(.{
            .name = "test_32",
            .root_source_file = .{ .path = "sbi.zig" },
            .target = target_32,
            .optimize = optimize,
        });
        test_step.dependOn(&test_32.step);
    }

    b.default_step = test_step;
}
