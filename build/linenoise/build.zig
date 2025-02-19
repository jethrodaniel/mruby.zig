// SPDX-FileCopyrightText: © 2025 Mark Delk <jethrodaniel@gmail.com>
//
// SPDX-License-Identifier: MIT

const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const src_dep = b.dependency("linenoise", .{});

    const lib = b.addStaticLibrary(.{
        .name = "linenoise",
        .target = target,
        .optimize = .ReleaseFast,
    });
    {
        lib.addIncludePath(src_dep.path(""));
        lib.linkLibC();

        lib.addCSourceFiles(.{
            .root = src_dep.path(""),
            .files = &.{"linenoise.c"},
            .flags = &.{},
        });

        lib.installHeader(src_dep.path("linenoise.h"), "linenoise.h");

        b.installArtifact(lib);
    }

    //--

    const example = b.addExecutable(.{
        .name = "example",
        .target = target,
        .optimize = optimize,
    });
    {
        example.linkLibrary(lib);
        example.addIncludePath(src_dep.path(""));

        example.addCSourceFile(.{ .file = src_dep.path("example.c"), .flags = &.{} });

        const run = b.addRunArtifact(example);
        const step = b.step("example", "Run example");
        step.dependOn(&run.step);

        b.installArtifact(example);
    }
}
