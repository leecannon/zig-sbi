// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

pub fn build(b: *std.Build) void {
    _ = b.addModule("sbi", .{
        .root_source_file = b.path("sbi.zig"),
    });

    const optimize = b.standardOptimizeOption(.{});

    buildTests(b, optimize);

    // check step
    {
        const check_test_exe = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("sbi.zig"),
                .target = b.resolveTargetQuery(.{ .cpu_arch = .riscv64 }),
            }),
        });
        const check_test_step = b.step("check", "");
        check_test_step.dependOn(&check_test_exe.step);
    }
}

fn buildTests(b: *std.Build, optimize: std.builtin.OptimizeMode) void {
    b.enable_qemu = true;

    const test_64 = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("sbi.zig"),
            .target = b.resolveTargetQuery(.{ .cpu_arch = .riscv64 }),
            .optimize = optimize,
        }),
    });
    const run_test_64 = b.addRunArtifact(test_64);
    run_test_64.failing_to_execute_foreign_is_an_error = false;

    const test_32 = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("sbi.zig"),
            .target = b.resolveTargetQuery(.{ .cpu_arch = .riscv32 }),
            .optimize = optimize,
        }),
    });
    const run_test_32 = b.addRunArtifact(test_32);
    run_test_32.failing_to_execute_foreign_is_an_error = false;

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_test_64.step);
    test_step.dependOn(&run_test_32.step);
}

const std = @import("std");
