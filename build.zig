const std = @import("std");

pub fn build(b: *std.Build) !void {

    const target = b.standardTargetOptions(.{}); 
    
    const exe = b.addExecutable(.{
        .name = "main",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = b.standardOptimizeOption(.{}),
    });


    if (target.result.os.tag == .windows) {
        exe.addIncludePath(b.path("deps/win/raylib/include"));
        exe.addLibraryPath(b.path("deps/win/raylib/lib"));
        exe.linkSystemLibrary("opengl32");
        exe.linkSystemLibrary("gdi32");
        exe.linkSystemLibrary("winmm");
    }
    exe.linkSystemLibrary("raylib");
    exe.linkLibC();

    b.installArtifact(exe);

    // create the run step
    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the program");
    run_step.dependOn(&run_exe.step);
}
