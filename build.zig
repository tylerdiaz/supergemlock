const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "supergemlock",
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the gem resolver");
    run_step.dependOn(&run_cmd.step);

    // Bundle CLI executable
    const bundle_exe = b.addExecutable(.{
        .name = "zig-bundle",
        .root_source_file = b.path("bundle.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(bundle_exe);

    const bundle_run_cmd = b.addRunArtifact(bundle_exe);
    bundle_run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        bundle_run_cmd.addArgs(args);
    }

    const bundle_step = b.step("bundle", "Run the bundle CLI");
    bundle_step.dependOn(&bundle_run_cmd.step);

    // Benchmark build
    const bench_exe = b.addExecutable(.{
        .name = "supergemlock_bench",
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });

    const bench_cmd = b.addRunArtifact(bench_exe);
    const bench_step = b.step("bench", "Run benchmarks");
    bench_step.dependOn(&bench_cmd.step);
}