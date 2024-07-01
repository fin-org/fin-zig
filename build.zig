const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const lib = b.addStaticLibrary(.{
        .name = "fin",
        .root_source_file = b.path("src/fin.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);
    const exe_tok = b.addExecutable(.{
        .name = "fin-tok",
        .root_source_file = b.path("src/tokenizer.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe_tok);
    const exe_fmt = b.addExecutable(.{
        .name = "fin-fmt",
        .root_source_file = b.path("src/parser.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe_fmt);

    const run_cmd = b.addRunArtifact(exe_fmt);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/fin.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
