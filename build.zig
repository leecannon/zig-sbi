const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("sbi", .{
        .root_source_file = .{ .path = "sbi.zig" },
        .target = target,
        .optimize = optimize,
    });
    _ = module;

    buildTests(b, optimize);
}

fn buildTests(b: *std.Build, optimize: std.builtin.OptimizeMode) void {
    const test_step = b.step("test", "Run library tests");

    const target_64 = b.resolveTargetQuery(.{ .cpu_arch = .riscv64, .os_tag = .freestanding });
    const build_test_64 = b.addStaticLibrary(.{
        .name = "test_64",
        .root_source_file = .{ .path = "sbi.zig" },
        .target = target_64,
        .optimize = optimize,
    });
    test_step.dependOn(&build_test_64.step);

    const target_32 = b.resolveTargetQuery(.{ .cpu_arch = .riscv32, .os_tag = .freestanding });
    const build_test_32 = b.addStaticLibrary(.{
        .name = "test_32",
        .root_source_file = .{ .path = "sbi.zig" },
        .target = target_32,
        .optimize = optimize,
    });
    test_step.dependOn(&build_test_32.step);
}
