const std = @import("std");

pub fn build(b: *std.Build) !void {
    // makes an exe, i guess lmao
    const exe = b.addExecutable(.{
        .name = "main",
        .root_source_file = b.path("src/main.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    });

    exe.linkLibC();
    // exe.addLibraryPath(b.path("./deps/raylib/lib")); // for Windows
    exe.linkSystemLibrary("raylib");

    b.installArtifact(exe);

    // create the run step
    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the program");
    run_step.dependOn(&run_exe.step);
}
