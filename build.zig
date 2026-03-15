const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSafe,
    });

    const mod = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (b.lazyDependency("zf", .{
        .target = target,
        .optimize = optimize,
    })) |zf| {
        mod.addImport("zf", zf.module("zf"));
    }

    const lib = b.addLibrary(.{
        .name = "deck-zf",
        .root_module = mod,
        .linkage = .dynamic,
    });
    b.installArtifact(lib);

    const test_step = b.step("test", "Run unit tests");
    const test_artifact = b.addTest(.{
        .root_module = mod,
    });
    test_step.dependOn(&b.addRunArtifact(test_artifact).step);
}
