const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const draw_step = b.step("draw", "build draw test");

    const flag_dep = b.dependency("flag", .{});
    const z2d_dep = b.dependency("z2d", .{});

    const main_exe = b.addExecutable(.{
        .name = "plot",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    main_exe.root_module.addImport("flag", flag_dep.module("flag"));

    const draw_test_exe = b.addExecutable(.{
        .name = "draw",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/draw.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    draw_test_exe.root_module.addImport("z2d", z2d_dep.module("z2d"));
    const install_draw = b.addInstallArtifact(draw_test_exe, .{});
    draw_step.dependOn(&install_draw.step);

    const install_exe = b.addInstallArtifact(main_exe, .{});
    b.getInstallStep().dependOn(&install_exe.step);
}
