// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

pub fn build(b: *std.Build) void {
    _ = b.addModule("sbi", .{
        .root_source_file = b.path("sbi.zig"),
    });

    b.enable_qemu = true;
    const test_step = b.step("test", "Run library tests");

    inline for (targets) |target| {
        const test_exe = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("sbi.zig"),
                .target = b.resolveTargetQuery(.{ .cpu_arch = target }),
            }),
        });
        const run_test_exe = b.addRunArtifact(test_exe);
        run_test_exe.failing_to_execute_foreign_is_an_error = false;
        test_step.dependOn(&run_test_exe.step);
    }

    const check_step = b.step("check", "");

    inline for (targets) |target| {
        const check_exe = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("sbi.zig"),
                .target = b.resolveTargetQuery(.{ .cpu_arch = target }),
            }),
        });
        check_step.dependOn(&check_exe.step);
    }
}

const targets: []const @Type(.enum_literal) = &.{ .riscv64, .riscv32 };

const std = @import("std");
