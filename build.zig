const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const flag_dep = b.dependency("flag", .{});

    const main_exe = b.addExecutable(.{
        .name = "plot",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    main_exe.root_module.addImport("flag", flag_dep.module("flag"));

    const install_exe = b.addInstallArtifact(main_exe, .{});
    b.getInstallStep().dependOn(&install_exe.step);
}
