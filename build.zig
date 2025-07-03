const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const main_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const main_exe = b.addExecutable(.{
        .name = "plot",
        .root_module = main_module,
    });

    const check_only = b.option(bool, "check", "check only") orelse false;

    if (check_only) {
        b.getInstallStep().dependOn(&main_exe.step);
    } else {
        b.installArtifact(main_exe);
    }
}
