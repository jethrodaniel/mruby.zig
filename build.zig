// SPDX-FileCopyrightText: © 2025 Mark Delk <jethrodaniel@gmail.com>
//
// SPDX-License-Identifier: MIT

const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mruby_dep = b.dependency("mruby", .{});
    const macos_dep = b.dependency("macos_cctools", .{});
    const linenoise_dep = b.dependency("linenoise", .{
        .target = target,
        .optimize = optimize,
    });

    //

    const custom_path = b.option(
        []const u8,
        "custom_path",
        "Path to custom files (default: ../..)",
    ) orelse "../..";

    //-- mruby/doc/guides/mrbconf.md

    // TODO: mruby sets this if no gems are provided
    const MRB_NO_GEMS = b.option(
        bool,
        "MRB_NO_GEMS",
        "Disable mgems",
    ) orelse false;
    const MRB_DEBUG = b.option(
        bool,
        "MRB_DEBUG",
        "Enable mrb_assert* macros",
    ) orelse false;
    const MRB_USE_DEBUG_HOOK = b.option(
        bool,
        "MRB_USE_DEBUG_HOOK",
        "Enable debug OPs",
    ) orelse false;
    const MRB_NO_PRESYM = true; // TODO
    const MRB_UTF8_STRING = b.option(
        bool,
        "MRB_UTF8_STRING",
        "Add UTF-8 support to character-oriented String methods (otherwise, US-ASCII)",
    ) orelse true;
    const MRB_STR_LENGTH_MAX = b.option(
        usize,
        "MRB_STR_LENGTH_MAX",
        "Maximum length of strings (0 to skip, default 1MB)",
    ) orelse 0; // 1048576
    const MRB_ARY_LENGTH_MAX = b.option(
        usize,
        "MRB_ARY_LENGTH_MAX",
        "Maximum length of arrays (0 to skip, default 1MB)",
    ) orelse 0; // 131072
    const MRB_NO_STDIO = b.option(
        bool,
        "MRB_NO_STDIO",
        "Disable <stdio.h> functions",
    ) orelse false;
    const MRB_INT64 = b.option(
        bool,
        "MRB_INT64",
        "Make mrb_int 64-bit",
    ) orelse true;

    //

    const default_mruby_gems: []const u8 =
        \\[
        \\  {"name": "mruby_proc_ext"},
        \\  {"name": "mruby_binding"},
        \\  {"name": "mruby_eval"},
        \\  {"name": "mruby_method"},
        \\  {"name": "mruby_proc_binding"},
        \\
        \\  {"name": "mruby_math"},
        \\  {"name": "mruby_complex"},
        \\  {"name": "mruby_cmath"},
        \\  {"name": "mruby_rational"},
        \\
        \\  {"name": "mruby_fiber"},
        \\  {"name": "mruby_enumerator"},
        \\  {"name": "mruby_enum_chain"},
        \\  {"name": "mruby_enum_lazy"},
        \\
        \\  {"name": "mruby_array_ext"},
        \\  {"name": "mruby_hash_ext"},
        \\
        \\  {"name": "mruby_time"},
        \\  {"name": "mruby_io"},
        \\  {"name": "mruby_socket"},
        \\
        \\  {"name": "mruby_objectspace"},
        \\  {"name": "mruby_os_memsize"},
        \\
        \\  {"name": "mruby_bigint"},
        \\  {"name": "mruby_catch"},
        \\  {"name": "mruby_class_ext"},
        \\  {"name": "mruby_compar_ext"},
        \\  {"name": "mruby_data"},
        \\  {"name": "mruby_dir"},
        \\  {"name": "mruby_enum_ext"},
        \\  {"name": "mruby_errno"},
        \\  {"name": "mruby_error"},
        \\  {"name": "mruby_exit"},
        \\  {"name": "mruby_kernel_ext"},
        \\  {"name": "mruby_metaprog"},
        \\  {"name": "mruby_numeric_ext"},
        \\  {"name": "mruby_object_ext"},
        \\  {"name": "mruby_pack"},
        \\  {"name": "mruby_print"},
        \\  {"name": "mruby_random"},
        \\  {"name": "mruby_range_ext"},
        \\  {"name": "mruby_set"},
        \\  {"name": "mruby_sleep"},
        \\  {"name": "mruby_sprintf"},
        \\  {"name": "mruby_string_ext"},
        \\  {"name": "mruby_struct"},
        \\  {"name": "mruby_symbol_ext"},
        \\  {"name": "mruby_test_inline_struct"},
        \\  {"name": "mruby_test"},
        \\  {"name": "mruby_toplevel_ext"},
        \\  {"name": "mruby_compiler"}
        \\]
    ;

    const mruby_gems_json_str = b.option(
        []const u8,
        "mruby_gems",
        "JSON array of gems",
    ) orelse default_mruby_gems;

    var scanner = std.json.Scanner.initCompleteInput(b.allocator, mruby_gems_json_str);
    var diagnostics = std.json.Diagnostics{};
    scanner.enableDiagnostics(&diagnostics);

    const user_gems = std.json.parseFromTokenSourceLeaky(
        []Mgem,
        b.allocator,
        &scanner,
        .{},
    ) catch |err| {
        std.log.err("{any} ({}, {})", .{ err, diagnostics.getLine(), diagnostics.getColumn() });

        var it = std.mem.splitSequence(u8, mruby_gems_json_str, "\n");
        var index: usize = 0;
        while (it.next()) |line| {
            std.log.err("{d}: {s}", .{ index + 1, line });
            index += 1;

            if (index == diagnostics.getLine()) {
                var prefix = std.ArrayList(u8).init(b.allocator);
                defer prefix.deinit();

                var prefix_index: usize = 0;
                while (prefix_index < diagnostics.getColumn()) {
                    try prefix.appendSlice("-"[0..]);
                    prefix_index += 1;
                }
                std.log.err("{s}^ ", .{prefix.items});
            }
        }
        @panic("failed to parse gems.json");
    };

    var gems = std.ArrayList(Mgem).init(b.allocator);
    defer gems.deinit();

    var builtin_gem_map = std.StringHashMap(Mgem).init(b.allocator);
    defer builtin_gem_map.deinit();

    for (builtin_gems) |gem| {
        try builtin_gem_map.put(gem.name, gem);
    }

    for (user_gems) |gem| {
        if (MRB_NO_GEMS and !std.mem.eql(u8, gem.name, "mruby_test"))
            continue;

        if (gem.builtin) {
            const builtin_gem = builtin_gem_map.get(gem.name) orelse @panic(
                b.fmt("missing builtin gem '{s}", .{gem.name}),
            );
            try gems.append(builtin_gem);
        } else {
            try gems.append(gem);
        }
    }

    const mruby_gems = gems.items;

    //

    const cflags = [_][]const u8{
        // "-fno-sanitize=undefined",
        // "-std=c99",
    };

    //

    const mrbc_exe = b.addExecutable(.{
        .name = "mrbc",
        .target = target,
        .optimize = optimize,
    });
    const host_mrbc_exe = b.addExecutable(.{
        .name = "host-mrbc",
        .target = b.host,
        .optimize = optimize,
    });
    {
        for ([_]*std.Build.Step.Compile{
            mrbc_exe,
            host_mrbc_exe,
        }) |exe| {
            exe.addCSourceFiles(.{
                .root = mruby_dep.path(""),
                .files = &([_][]const u8{
                    // NOTE: manually providing mruby-compiler dependency
                    "mrbgems/mruby-compiler/core/y.tab.c",
                    "mrbgems/mruby-compiler/core/codegen.c",

                    "mrbgems/mruby-bin-mrbc/tools/mrbc/mrbc.c",
                    "mrbgems/mruby-bin-mrbc/tools/mrbc/stub.c",
                } ++ mruby_core_c_files),
                .flags = &cflags,
            });

            exe.defineCMacro("MRB_NO_PRESYM", "1");

            exe.addIncludePath(mruby_dep.path("include"));
            exe.linkLibC();

            b.installArtifact(exe);

            const run = b.addRunArtifact(exe);
            if (b.args) |args| run.addArgs(args);
            const step = b.step(exe.name, b.fmt("run '{s}'", .{exe.name}));
            step.dependOn(&run.step);
        }
    }

    //

    const mruby_lib = b.addStaticLibrary(.{
        .name = "libruby",
        .target = target,
        .optimize = optimize,
    });
    {
        const lib = mruby_lib;

        // non-gem things
        {
            lib.addIncludePath(mruby_dep.path("include"));
            lib.installHeadersDirectory(mruby_dep.path("include"), "", .{});
            lib.linkLibC();

            if (target.result.os.tag == .macos) {
                lib.addIncludePath(macos_dep.path("include"));
            } else if (target.result.os.tag == .linux) {
                lib.defineCMacro("_XOPEN_SOURCE", "700");
                lib.defineCMacro("_BSD_SOURCE", "1");
            }

            lib.addCSourceFiles(.{
                .root = mruby_dep.path(""),
                .files = &mruby_core_c_files,
                .flags = &cflags,
            });

            // mruby/tasks/mrblib.rake
            {
                const mrbc_cmd = b.addRunArtifact(host_mrbc_exe);
                if (optimize == .Debug) mrbc_cmd.addArg("-g -B%{funcname} -o-");
                mrbc_cmd.addArgs(&.{ "-B", "mrblib_irep", "-o" });
                const mrblib_rbfiles_c = mrbc_cmd.addOutputFileArg("mrblib_rbfiles.c");
                for ([_][]const u8{
                    "mrblib/00class.rb",
                    "mrblib/00kernel.rb",
                    "mrblib/10error.rb",
                    "mrblib/array.rb",
                    "mrblib/compar.rb",
                    "mrblib/enum.rb",
                    "mrblib/hash.rb",
                    "mrblib/kernel.rb",
                    "mrblib/numeric.rb",
                    "mrblib/range.rb",
                    "mrblib/string.rb",
                    "mrblib/symbol.rb",
                }) |file| {
                    mrbc_cmd.addFileArg(mruby_dep.path(file));
                }

                lib.addCSourceFile(.{ .file = mrblib_rbfiles_c, .flags = &cflags });
                lib.addCSourceFile(.{
                    .file = b.addWriteFiles().add("mrblib.c",
                        \\/*
                        \\ * This file is loading the mrblib
                        \\ *
                        \\ * IMPORTANT:
                        \\ *   This file was generated!
                        \\ *   All manual changes will get lost.
                        \\ */
                        \\
                        \\#include <mruby.h>
                        \\#include <mruby/irep.h>
                        \\#include <mruby/proc.h>
                        \\
                        \\extern const uint8_t mrblib_irep[];
                        \\
                        \\void
                        \\mrb_init_mrblib(mrb_state *mrb)
                        \\{
                        \\  mrb_load_irep(mrb, mrblib_irep);
                        \\}
                    ),
                    .flags = &cflags,
                });
            }
        }

        // gems
        {
            // for each gem named NAME
            //
            // 1. compile rb files to NAME_rbfiles.c, which contains gem_mrblib_irep_NAME
            // 2. generate NAME/gem_init.c, which loads the rbfiles
            // 3. add NAME/gem_init.c and any c sources to libmruby
            //
            // NOTE: we could build a static lib for each gem to cache better?

            // mruby/lib/mruby/gem.rb
            for (mruby_gems) |gem| {
                // compile gem's ruby files
                if (gem.rbfiles.len > 0) {
                    const mrbc_cmd = b.addRunArtifact(host_mrbc_exe);
                    if (optimize == .Debug) mrbc_cmd.addArg("-g -B%{funcname} -o-");
                    mrbc_cmd.addArgs(&.{
                        "-B",
                        b.fmt("gem_mrbgem_irep_{s}", .{gem.name}),
                        "-o",
                    });
                    const gem_rbfiles_c = mrbc_cmd.addOutputFileArg(
                        b.fmt("mrbgems/{s}/gem_init.rb.c", .{gem.name}),
                    );

                    for (gem.rbfiles) |file| {
                        const path: std.Build.LazyPath = if (gem.builtin)
                            mruby_dep.path(file)
                        else
                            .{ .cwd_relative = b.pathJoin(&.{ custom_path, file }) };

                        mrbc_cmd.addFileArg(path);
                    }

                    lib.addCSourceFile(.{
                        .file = gem_rbfiles_c,
                        .flags = &cflags,
                    });
                }

                var gem_init_content = std.ArrayList(u8).init(b.allocator);
                defer gem_init_content.deinit();

                try gem_init_content.appendSlice(
                    \\/*
                    \\ * This file is loading the irep
                    \\ * Ruby GEM code.
                    \\ *
                    \\ * IMPORTANT:
                    \\ *   This file was generated!
                    \\ *   All manual changes will get lost.
                    \\ */
                    \\
                    \\#include <stdlib.h>
                    \\#include <mruby.h>
                    \\#include <mruby/proc.h>
                    \\
                [0..]);

                if (gem.rbfiles.len > 0)
                    try gem_init_content.appendSlice(b.fmt(
                        \\
                        \\extern const uint8_t gem_mrbgem_irep_{s}[];
                        \\
                    , .{gem.name})[0..]);

                if (gem.srcs.len > 0 and !gem.external_gem_init and !gem.is_core_gem)
                    try gem_init_content.appendSlice(b.fmt(
                        \\
                        \\void mrb_{s}_gem_init(mrb_state *mrb);
                        \\void mrb_{s}_gem_final(mrb_state *mrb);
                        \\
                    , .{ gem.name, gem.name })[0..]);

                if (gem.external_gem_init)
                    try gem_init_content.appendSlice(b.fmt(
                        \\
                        \\extern void mrb_{s}_gem_init(mrb_state *mrb);
                        \\extern void mrb_{s}_gem_final(mrb_state *mrb);
                        \\
                    , .{ gem.name, gem.name })[0..]);

                try gem_init_content.appendSlice(b.fmt(
                    \\
                    \\void GENERATED_TMP_mrb_{s}_gem_init(mrb_state *mrb) {{
                    \\
                , .{gem.name})[0..]);

                if ((gem.srcs.len > 0 or gem.external_gem_init) and !gem.is_core_gem)
                    try gem_init_content.appendSlice(b.fmt(
                        \\  mrb_{s}_gem_init(mrb);
                        \\
                    , .{gem.name})[0..]);

                if (gem.rbfiles.len > 0)
                    try gem_init_content.appendSlice(b.fmt(
                        \\  mrb_load_irep(mrb, gem_mrbgem_irep_{s});
                        \\
                    , .{gem.name})[0..]);

                try gem_init_content.appendSlice(
                    \\}
                    \\
                [0..]);

                try gem_init_content.appendSlice(b.fmt(
                    \\
                    \\void GENERATED_TMP_mrb_{s}_gem_final(mrb_state *mrb) {{
                    \\
                , .{gem.name})[0..]);

                if ((gem.srcs.len > 0 or gem.external_gem_init) and !gem.is_core_gem)
                    try gem_init_content.appendSlice(b.fmt(
                        \\  mrb_{s}_gem_final(mrb);
                        \\
                    , .{gem.name})[0..]);

                try gem_init_content.appendSlice(
                    \\}
                    \\
                [0..]);

                lib.addCSourceFile(.{
                    .file = b.addWriteFiles().add(
                        b.fmt("mrbgems/{s}/gem_init.c", .{gem.name}),
                        gem_init_content.items,
                    ),
                    .flags = &cflags,
                });

                // add gem's c source files
                {
                    if (gem.srcs.len == 0) continue;

                    const path: std.Build.LazyPath = if (gem.builtin)
                        mruby_dep.path("")
                    else
                        .{ .cwd_relative = custom_path };

                    for (gem.includePaths) |include_path| {
                        lib.addIncludePath(.{ .cwd_relative = b.pathJoin(
                            &.{ path.getPath(b), include_path },
                        ) });
                    }

                    lib.addCSourceFiles(.{
                        .root = path,
                        .files = gem.srcs,
                        .flags = &cflags,
                    });
                }
            }

            // mruby/tasks/mrbgems.rake
            //
            // generate mrbgems/gem_init.c
            {
                var gem_init_content = std.ArrayList(u8).init(b.allocator);
                defer gem_init_content.deinit();

                try gem_init_content.appendSlice(
                    \\/*
                    \\ * This file contains a list of all
                    \\ * initializing methods which are
                    \\ * necessary to bootstrap all gems.
                    \\ *
                    \\ * IMPORTANT:
                    \\ *   This file was generated!
                    \\ *   All manual changes will get lost.
                    \\ */
                    \\
                    \\#include <mruby.h>
                    \\#include <mruby/proc.h>
                    \\#include <mruby/error.h>
                    \\
                    \\
                [0..]);

                for (mruby_gems) |gem| {
                    try gem_init_content.appendSlice(b.fmt(
                        \\void GENERATED_TMP_mrb_{s}_gem_init(mrb_state *mrb);
                        \\void GENERATED_TMP_mrb_{s}_gem_final(mrb_state *mrb);
                        \\
                    , .{ gem.name, gem.name })[0..]);
                }

                try gem_init_content.appendSlice(
                    \\
                    \\static const struct {
                    \\  void (*init)(mrb_state*);
                    \\  void (*final)(mrb_state*);
                    \\} gem_funcs[] = {
                    \\
                );

                for (mruby_gems) |gem| {
                    try gem_init_content.appendSlice(b.fmt(
                        \\  {{
                        \\    GENERATED_TMP_mrb_{s}_gem_init,
                        \\    GENERATED_TMP_mrb_{s}_gem_final,
                        \\  }},
                        \\
                    , .{ gem.name, gem.name })[0..]);
                }

                try gem_init_content.appendSlice(
                    \\};
                    \\
                    \\#define NUM_GEMS ((int)(sizeof(gem_funcs) / sizeof(gem_funcs[0])))
                    \\
                    \\struct final_mrbgems {
                    \\  int i;
                    \\  int ai;
                    \\};
                    \\
                    \\static mrb_value
                    \\final_mrbgems_body(mrb_state *mrb, void *ud) {
                    \\  struct final_mrbgems *p = (struct final_mrbgems*)ud;
                    \\  for (; p->i >= 0; p->i--) {
                    \\    gem_funcs[p->i].final(mrb);
                    \\    mrb_gc_arena_restore(mrb, p->ai);
                    \\  }
                    \\  return mrb_nil_value();
                    \\}
                    \\
                    \\static void
                    \\mrb_final_mrbgems(mrb_state *mrb) {
                    \\  struct final_mrbgems a = { NUM_GEMS - 1, mrb_gc_arena_save(mrb) };
                    \\  for (; a.i >= 0; a.i--) {
                    \\    mrb_protect_error(mrb, final_mrbgems_body, &a, NULL);
                    \\    mrb_gc_arena_restore(mrb, a.ai);
                    \\  }
                    \\}
                    \\
                    \\void
                    \\mrb_init_mrbgems(mrb_state *mrb) {
                    \\  int ai = mrb_gc_arena_save(mrb);
                    \\  for (int i = 0; i < NUM_GEMS; i++) {
                    \\    gem_funcs[i].init(mrb);
                    \\    mrb_gc_arena_restore(mrb, ai);
                    \\    mrb_vm_ci_env_clear(mrb, mrb->c->cibase);
                    \\    if (mrb->exc) {
                    \\      mrb_exc_raise(mrb, mrb_obj_value(mrb->exc));
                    \\    }
                    \\  }
                    \\  mrb_state_atexit(mrb, mrb_final_mrbgems);
                    \\}
                    \\
                );

                lib.addCSourceFile(.{
                    .file = b.addWriteFiles().add("mrbgems/gem_init.c", gem_init_content.items),
                    .flags = &cflags,
                });
            }

            for (mruby_gems) |gem| {
                // TODO: cleaner per-gem linkage
                if (std.mem.eql(u8, gem.name, "mruby_io") and target.result.os.tag == .windows)
                    lib.linkSystemLibrary("ws2_32");

                for (gem.defines) |define|
                    lib.defineCMacro(define, "1");
            }
        }

        b.installArtifact(lib);
    }

    //--

    const mruby_exe = b.addExecutable(.{
        .name = "mruby",
        .target = target,
        .optimize = optimize,
    });
    {
        const exe = mruby_exe;

        exe.addCSourceFiles(.{
            .root = mruby_dep.path(""),
            .files = &.{"mrbgems/mruby-bin-mruby/tools/mruby/mruby.c"},
            .flags = &cflags,
        });
        if (MRB_NO_GEMS)
            exe.addCSourceFiles(.{ .root = mruby_dep.path(""), .files = &.{
                "mrbgems/mruby-compiler/core/y.tab.c",
                "mrbgems/mruby-compiler/core/codegen.c",
            }, .flags = &cflags });

        exe.linkLibrary(mruby_lib);

        b.installArtifact(exe);

        const run = b.addRunArtifact(exe);
        if (b.args) |args| run.addArgs(args);
        const step = b.step(exe.name, b.fmt("run '{s}'", .{exe.name}));
        step.dependOn(&run.step);
    }

    //--

    const mirb_exe = b.addExecutable(.{
        .name = "mirb",
        .target = target,
        .optimize = optimize,
    });
    {
        const exe = mirb_exe;

        exe.addCSourceFiles(.{
            .root = mruby_dep.path(""),
            .files = &.{"mrbgems/mruby-bin-mirb/tools/mirb/mirb.c"},
            .flags = &cflags,
        });

        if (MRB_NO_GEMS)
            exe.addCSourceFiles(.{ .root = mruby_dep.path(""), .files = &.{
                "mrbgems/mruby-compiler/core/y.tab.c",
                "mrbgems/mruby-compiler/core/codegen.c",
            }, .flags = &cflags });

        exe.linkLibrary(mruby_lib);

        if (target.result.os.tag != .windows) {
            exe.defineCMacro("MRB_USE_LINENOISE", "1");
            exe.linkLibrary(linenoise_dep.artifact("linenoise"));
        }

        b.installArtifact(exe);

        const run = b.addRunArtifact(exe);
        if (b.args) |args| run.addArgs(args);
        const step = b.step(exe.name, b.fmt("run '{s}'", .{exe.name}));
        step.dependOn(&run.step);
    }

    // NOTE: requires enabling the debug hook, and including mruby-eval, e.g,
    //    zig build mrdb -DMRB_USE_DEBUG_HOOK=true -- sample.rb
    const mrdb_exe = b.addExecutable(.{
        .name = "mrdb",
        .target = target,
        .optimize = optimize,
    });
    {
        const exe = mrdb_exe;

        exe.addCSourceFiles(.{
            .root = mruby_dep.path(""),
            .files = &.{
                "mrbgems/mruby-bin-debugger/tools/mrdb/apibreak.c",
                "mrbgems/mruby-bin-debugger/tools/mrdb/apilist.c",
                "mrbgems/mruby-bin-debugger/tools/mrdb/apiprint.c",
                "mrbgems/mruby-bin-debugger/tools/mrdb/apistring.c",
                "mrbgems/mruby-bin-debugger/tools/mrdb/cmdbreak.c",
                "mrbgems/mruby-bin-debugger/tools/mrdb/cmdmisc.c",
                "mrbgems/mruby-bin-debugger/tools/mrdb/cmdprint.c",
                "mrbgems/mruby-bin-debugger/tools/mrdb/cmdrun.c",
                "mrbgems/mruby-bin-debugger/tools/mrdb/mrdb.c",
            },
            .flags = &cflags,
        });
        exe.addIncludePath(mruby_dep.path("mrbgems/mruby-bin-debugger/tools/mrdb"));
        exe.linkLibrary(mruby_lib);

        if (MRB_USE_DEBUG_HOOK)
            b.installArtifact(exe);

        const run = b.addRunArtifact(exe);
        if (b.args) |args| run.addArgs(args);
        const step = b.step(exe.name, b.fmt("run '{s}'", .{exe.name}));
        step.dependOn(&run.step);
    }

    const mruby_strip_exe = b.addExecutable(.{
        .name = "mruby-strip",
        .target = target,
        .optimize = optimize,
    });
    {
        const exe = mruby_strip_exe;

        exe.addCSourceFiles(.{
            .root = mruby_dep.path(""),
            .files = &.{
                // NOTE: requires mruby-compiler dependency
                // "mrbgems/mruby-compiler/core/y.tab.c",
                // "mrbgems/mruby-compiler/core/codegen.c",

                "mrbgems/mruby-bin-strip/tools/mruby-strip/mruby-strip.c",
            },
            .flags = &cflags,
        });
        exe.linkLibrary(mruby_lib);

        b.installArtifact(exe);

        const run = b.addRunArtifact(exe);
        if (b.args) |args| run.addArgs(args);
        const step = b.step(exe.name, b.fmt("run '{s}'", .{exe.name}));
        step.dependOn(&run.step);
    }

    //--

    const mrbtest = b.addExecutable(.{
        .name = "mrbtest",
        .target = target,
        .optimize = optimize,
    });
    {
        const exe = mrbtest;

        // mrbgems/mruby-dir/test/dirtest.c:69:58: error: use of undeclared identifier 'P_tmpdir'
        // mrbgems/mruby-dir/test/dirtest.c:70:7: error: call to undeclared function 'mkdtemp'; ISO C99 and later do not support implicit function declarations
        if (target.result.os.tag == .linux) {
            if (target.result.abi == .musl) {
                exe.defineCMacro("_XOPEN_SOURCE", "1");
            } else {
                exe.defineCMacro("_GNU_SOURCE", "1");
            }
        }

        // driver
        exe.addCSourceFiles(.{
            .root = mruby_dep.path(""),
            .files = &.{
                "mrbgems/mruby-test/driver.c",
                "mrbgems/mruby-test/vformat.c",
            },
            .flags = &cflags,
        });

        // test/assert.rb
        {
            const mrbc_cmd = b.addRunArtifact(host_mrbc_exe);
            mrbc_cmd.addArgs(&.{
                "-g -B%{funcname} -o-", // needed for backtrace tests
                "-B",
                "mrbtest_assert_irep",
                "-o",
            });

            const assert_c = mrbc_cmd.addOutputFileArg("assert.c");
            mrbc_cmd.addFileArg(mruby_dep.path("test/assert.rb"));

            exe.addCSourceFile(.{ .file = assert_c, .flags = &cflags });
        }

        for (mruby_gems) |gem| {
            var gem_test_content = std.ArrayList(u8).init(b.allocator);
            defer gem_test_content.deinit();

            if (gem.test_rbfiles.len == 0) continue;

            try gem_test_content.appendSlice(b.fmt(
                \\/*
                \\ * This file contains a test code for {s} gem.
                \\ *
                \\ * IMPORTANT:
                \\ *   This file was generated!
                \\ *   All manual changes will get lost.
                \\ */
                \\
                \\#include <stdio.h>
                \\#include <stdlib.h>
                \\#include <mruby.h>
                \\#include <mruby/irep.h>
                \\#include <mruby/variable.h>
                \\
                \\extern const uint8_t mrbtest_assert_irep[];
                \\
                \\
            , .{gem.name})[0..]);

            // setup irep for all the test rbfiles
            for (gem.test_rbfiles, 0..) |file, index| {
                try gem_test_content.appendSlice(b.fmt(
                    \\extern const uint8_t gem_test_irep_{s}_{d}[];
                    \\
                , .{ gem.name, index })[0..]);

                const mrbc_cmd = b.addRunArtifact(host_mrbc_exe);
                mrbc_cmd.addArgs(&.{
                    "-g -B%{funcname} -o-", // needed for backtrace tests
                    "-B",
                    b.fmt("gem_test_irep_{s}_{d}", .{ gem.name, index }),
                    "-o",
                });

                const gem_test_irep_c = mrbc_cmd.addOutputFileArg(
                    b.fmt("{s}/gem_test.rb-{d}.c", .{ gem.name, index }),
                );

                const path: std.Build.LazyPath = if (gem.builtin)
                    mruby_dep.path("")
                else
                    .{ .cwd_relative = custom_path };

                mrbc_cmd.addFileArg(.{
                    .cwd_relative = b.pathJoin(&.{ path.getPath(b), file }),
                });

                exe.addCSourceFile(.{
                    .file = gem_test_irep_c,
                    .flags = &cflags,
                });
            }

            if (gem.test_srcs.len > 0)
                try gem_test_content.appendSlice(b.fmt(
                    \\void mrb_{s}_gem_test(mrb_state *mrb);
                    \\
                , .{gem.name})[0..]);

            var dependencies = std.ArrayList([]const u8).init(b.allocator);
            defer dependencies.deinit();

            for (gem.dependencies) |dep|
                try dependencies.append(dep[0..]);
            try dependencies.append(gem.name);

            // TODO: tsort
            for (dependencies.items) |dep| {
                try gem_test_content.appendSlice(b.fmt(
                    \\
                    \\void GENERATED_TMP_mrb_{s}_gem_init(mrb_state *mrb);
                    \\void GENERATED_TMP_mrb_{s}_gem_final(mrb_state *mrb);
                    \\
                , .{ dep, dep })[0..]);
            }

            try gem_test_content.appendSlice(b.fmt(
                \\
                \\
                \\void mrb_init_test_driver(mrb_state *mrb, mrb_bool verbose);
                \\void mrb_t_pass_result(mrb_state *dst, mrb_state *src);
                \\
                \\void GENERATED_TMP_mrb_{s}_gem_test(mrb_state *mrb) {{
                \\
            , .{
                gem.name,
            })[0..]);

            if (gem.test_rbfiles.len > 0) {
                try gem_test_content.appendSlice(b.fmt(
                    \\  mrb_state *mrb2 = mrb_open_core(mrb_default_allocf, NULL);
                    \\  if (mrb2 == NULL) {{
                    \\    fprintf(stderr, "Invalid mrb_state, exiting %s", __func__);
                    \\    exit(EXIT_FAILURE);
                    \\  }}
                    \\  int ai = mrb_gc_arena_save(mrb2);
                    \\  mrb_const_set(
                    \\    mrb2,
                    \\    mrb_obj_value(mrb2->object_class),
                    \\    mrb_intern_lit(mrb2, "GEMNAME"),
                    \\    mrb_str_new(mrb2, "{s}", {d})
                    \\  );
                    \\  mrb_gc_arena_restore(mrb2, ai);
                    \\  mrb_load_irep(mrb2, mrbtest_assert_irep);
                    \\
                , .{
                    gem.name,
                    gem.name.len,
                })[0..]);

                for (dependencies.items) |dep| {
                    try gem_test_content.appendSlice(b.fmt(
                        \\
                        \\  GENERATED_TMP_mrb_{s}_gem_init(mrb2);
                        \\  mrb_state_atexit(mrb2, GENERATED_TMP_mrb_{s}_gem_final);
                        \\
                    , .{ dep, dep })[0..]);
                }
                try gem_test_content.appendSlice(
                    \\  mrb_init_test_driver(
                    \\    mrb2,
                    \\    mrb_test(mrb_gv_get(mrb, mrb_intern_lit(mrb, "$mrbtest_verbose")))
                    \\  );
                    \\  mrb_gc_arena_restore(mrb2, ai);
                    \\
                    \\
                [0..]);

                for (gem.test_rbfiles, 0..) |_, index| {
                    // TODO: TEST_ARGS
                    if (gem.test_srcs.len > 0)
                        try gem_test_content.appendSlice(b.fmt(
                            \\  mrb_gc_arena_restore(mrb2, ai);
                            \\  mrb_{s}_gem_test(mrb2);
                            \\
                        , .{gem.name})[0..]);

                    try gem_test_content.appendSlice(b.fmt(
                        \\  mrb_gc_arena_restore(mrb2, ai);
                        \\  mrb_load_irep(mrb2, gem_test_irep_{s}_{d});
                        \\  if (mrb2->exc) {{
                        \\    mrb_print_error(mrb2);
                        \\    mrb_close(mrb2);
                        \\    exit(EXIT_FAILURE);
                        \\  }}
                        \\
                        \\
                    , .{ gem.name, index })[0..]);
                }
                try gem_test_content.appendSlice(
                    \\  mrb_t_pass_result(mrb, mrb2);
                    \\  mrb_close(mrb2);
                    \\}
                    \\
                [0..]);
            }

            exe.addCSourceFile(.{
                .file = b.addWriteFiles().add(
                    b.fmt("mrbgems/{s}/gem_test.c", .{gem.name}),
                    gem_test_content.items,
                ),
                .flags = &cflags,
            });

            // include paths, c test sources
            {
                const path: std.Build.LazyPath = if (gem.builtin)
                    mruby_dep.path("")
                else
                    .{ .cwd_relative = custom_path };

                for (gem.includePaths) |file| {
                    mrbtest.addIncludePath(.{
                        .cwd_relative = b.pathJoin(&.{ path.getPath(b), file }),
                    });
                }

                for (gem.test_srcs) |file| {
                    exe.addCSourceFile(.{
                        .file = .{ .cwd_relative = b.pathJoin(&.{ path.getPath(b), file }) },
                        .flags = &cflags,
                    });
                }
            }
        }

        // mrbgems/mruby-test/mrbtest.c
        {
            var mrbtest_content = std.ArrayList(u8).init(b.allocator);
            defer mrbtest_content.deinit();

            try mrbtest_content.appendSlice(
                \\// mrbgems/mruby-test/mrbtest.c - list of all test functions
                \\
                \\#include <mruby.h>
                \\#include <mruby/variable.h>
                \\#include <mruby/array.h>
                \\
                \\
            [0..]);

            for (mruby_gems) |gem| {
                if (gem.test_rbfiles.len == 0) continue;

                try mrbtest_content.appendSlice(b.fmt(
                    \\void GENERATED_TMP_mrb_{s}_gem_test(mrb_state *mrb);
                    \\
                , .{
                    gem.name,
                })[0..]);
            }

            try mrbtest_content.appendSlice(
                \\
                \\void mrbgemtest_init(mrb_state* mrb) {
                \\  int ai = mrb_gc_arena_save(mrb);
                \\
            [0..]);

            for (mruby_gems) |gem| {
                if (gem.test_rbfiles.len == 0) continue;

                try mrbtest_content.appendSlice(b.fmt(
                    \\  GENERATED_TMP_mrb_{s}_gem_test(mrb);
                    \\
                , .{
                    gem.name,
                })[0..]);
            }

            try mrbtest_content.appendSlice(
                \\  mrb_gc_arena_restore(mrb, ai);
                \\}
                \\
            [0..]);

            exe.addCSourceFile(.{
                .file = b.addWriteFiles().add(
                    "mrbgems/mruby-test/mrbtest.c",
                    mrbtest_content.items,
                ),
                .flags = &cflags,
            });
        }

        //

        exe.linkLibrary(mruby_lib);

        b.installArtifact(exe);

        const run = b.addRunArtifact(exe);
        if (b.args) |args| run.addArgs(args);
        const step = b.step(exe.name, b.fmt("run '{s}'", .{exe.name}));
        step.dependOn(&run.step);
    }

    for ([_]*std.Build.Step.Compile{
        mruby_lib,
        mirb_exe,
        mruby_exe,
        mrdb_exe,
        mruby_strip_exe,
        mrbtest,
    }) |obj| {
        obj.defineCMacro("MRB_STR_LENGTH_MAX", b.fmt("{any}", .{MRB_STR_LENGTH_MAX}));
        obj.defineCMacro("MRB_ARY_LENGTH_MAX", b.fmt("{any}", .{MRB_ARY_LENGTH_MAX}));
        if (MRB_NO_GEMS)
            obj.defineCMacro("MRB_NO_GEMS", "1");
        if (MRB_NO_PRESYM)
            obj.defineCMacro("MRB_NO_PRESYM", "1");
        if (MRB_UTF8_STRING)
            obj.defineCMacro("MRB_UTF8_STRING", "1");
        if (MRB_DEBUG)
            obj.defineCMacro("MRB_DEBUG", "1");
        if (MRB_USE_DEBUG_HOOK)
            obj.defineCMacro("MRB_USE_DEBUG_HOOK", "1");
        if (MRB_NO_STDIO)
            obj.defineCMacro("MRB_NO_STDIO", "1");
        if (MRB_INT64)
            obj.defineCMacro("MRB_INT64", "1");

        //  from <mruby/value.h>, <mach-o/getsect.h>
        if (target.result.os.tag == .macos)
            obj.addIncludePath(macos_dep.path("include"));
    }

    //

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.addWriteFiles().add("input.c",
        // add more headers as needed
            \\#include <mruby.h>
            \\#include <mruby/compile.h>
            \\#include <mruby/data.h>
            \\#include <mruby/string.h>
            \\#include <mruby/variable.h>
            \\
            \\#include <stdio.h>
        ),
        .target = b.host,
        .optimize = .ReleaseFast,
    });
    {
        translate_c.addIncludeDir(mruby_dep.path("include").getPath(b));
    }

    // TODO: this won't be needed after translate-c supports bitfields
    const fix_translation_exe = b.addExecutable(.{
        .name = "fix-translation",
        .target = b.host,
        .optimize = .ReleaseFast,
        .root_source_file = b.path("src/fix_translation.zig"),
    });
    const fix_translation = b.addRunArtifact(fix_translation_exe);
    {
        fix_translation.addFileArg(translate_c.getOutput());
    }
    const fixed_translation = fix_translation.captureStdOut();

    const module = b.addModule("mruby", .{
        .root_source_file = b.addWriteFiles().add("src/lib.zig",
            \\pub const c = @import("c");
        ),
    });
    {
        module.addImport("c", b.createModule(.{
            .root_source_file = fixed_translation,
        }));

        module.linkLibrary(mruby_lib);
    }

    //--------------------------------

    const example_c = b.addExecutable(.{
        .name = "example-c",
        .target = target,
        .optimize = optimize,
    });
    {
        example_c.addCSourceFiles(.{
            .files = &.{"src/example.c"},
            .flags = &.{},
        });
        example_c.linkLibrary(mruby_lib);

        const run = b.addRunArtifact(example_c);
        run.expectExitCode(42);
        run.expectStdOutEqual(
            \\Time
            \\sizeof(mrb_gc): 104
            \\
        );

        const step = b.step("example-c", "");
        step.dependOn(&run.step);
    }

    //

    const example_ruby = b.addRunArtifact(mruby_exe);
    {
        example_ruby.addArgs(&.{"-r"});
        example_ruby.addFileArg(b.path("src/example.rb"));
        example_ruby.expectStdOutEqual(
            \\mruby 3.3.0 (2024-02-14)
            \\mruby - Copyright (c) 2010-2024 mruby developers
            \\#<Example:42>
            \\
        );

        const step = b.step("example-rb", "");
        step.dependOn(&example_ruby.step);
    }

    //

    const example_zig = b.addExecutable(.{
        .name = "example-zig",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/example.zig"),
    });
    {
        example_zig.root_module.addImport("mruby", module);

        const run = b.addRunArtifact(example_zig);

        const step = b.step("example-zig", "");
        step.dependOn(&run.step);
    }
}

const Mgem = struct {
    // e.g, mruby_time
    name: []const u8,

    // c sources
    srcs: []const []const u8 = &.{},
    includePaths: []const []const u8 = &.{},
    rbfiles: []const []const u8 = &.{},
    test_rbfiles: []const []const u8 = &.{},

    test_srcs: []const []const u8 = &.{},
    external_test_init: bool = false,
    builtin: bool = true,

    external_gem_init: bool = false,

    dependencies: []const []const u8 = &.{},
    // TODO: actually use this
    test_dependencies: []const []const u8 = &.{},

    defines: []const []const u8 = &.{},

    // if true, then gem_{init,final} aren't implemented
    is_core_gem: bool = false,
};

const builtin_gems = [_]Mgem{
    Mgem{
        .name = "mruby_array_ext",
        .srcs = &.{"mrbgems/mruby-array-ext/src/array.c"},
        .rbfiles = &.{"mrbgems/mruby-array-ext/mrblib/array.rb"},
        .test_rbfiles = &.{"mrbgems/mruby-array-ext/test/array.rb"},
    },
    Mgem{
        .name = "mruby_bigint",
        .srcs = &.{"mrbgems/mruby-bigint/core/bigint.c"},
        .includePaths = &.{"mrbgems/mruby-bigint/core"},
        .test_rbfiles = &.{"mrbgems/mruby-bigint/test/bigint.rb"},
        .defines = &.{"MRB_USE_BIGINT"},
        .is_core_gem = true,
    },
    Mgem{
        .name = "mruby_binding",
        .srcs = &.{"mrbgems/mruby-binding/src/binding.c"},
        .test_srcs = &.{"mrbgems/mruby-binding/test/binding.c"},
        .test_rbfiles = &.{"mrbgems/mruby-binding/test/binding.rb"},
        .dependencies = &.{"mruby_proc_ext"},
    },
    Mgem{
        .name = "mruby_catch",
        .rbfiles = &.{"mrbgems/mruby-catch/mrblib/catch.rb"},
        .srcs = &.{"mrbgems/mruby-catch/src/catch.c"},
        .test_rbfiles = &.{"mrbgems/mruby-catch/test/catch.rb"},
    },
    Mgem{
        .name = "mruby_class_ext",
        .rbfiles = &.{"mrbgems/mruby-class-ext/mrblib/module.rb"},
        .srcs = &.{"mrbgems/mruby-class-ext/src/class.c"},
        .test_rbfiles = &.{
            "mrbgems/mruby-class-ext/test/class.rb",
            "mrbgems/mruby-class-ext/test/module.rb",
        },
    },
    Mgem{
        .name = "mruby_cmath",
        .srcs = &.{"mrbgems/mruby-cmath/src/cmath.c"},
        .test_rbfiles = &.{"mrbgems/mruby-cmath/test/cmath.rb"},
        .dependencies = &.{
            // TODO: don't require specifying all dependencies
            "mruby_math",
            "mruby_complex",
        },
        .defines = &.{"MRB_USE_COMPLEX"},
    },
    Mgem{
        .name = "mruby_compar_ext",
        .rbfiles = &.{"mrbgems/mruby-compar-ext/mrblib/compar.rb"},
        .test_rbfiles = &.{}, // TODO: missing spec coverage here
    },
    Mgem{
        .name = "mruby_compiler",
        .srcs = &.{
            "mrbgems/mruby-compiler/core/y.tab.c",
            "mrbgems/mruby-compiler/core/codegen.c",
        },
        .includePaths = &.{"mrbgems/mruby-compiler/core"},
        .test_rbfiles = &.{}, // TODO: spec coverage
        .is_core_gem = true,
    },
    Mgem{
        .name = "mruby_complex",
        .rbfiles = &.{"mrbgems/mruby-complex/mrblib/complex.rb"},
        .srcs = &.{"mrbgems/mruby-complex/src/complex.c"},
        .test_rbfiles = &.{"mrbgems/mruby-complex/test/complex.rb"},
        .dependencies = &.{"mruby_math"},
    },
    Mgem{
        .name = "mruby_data",
        .srcs = &.{"mrbgems/mruby-data/src/data.c"},
        .test_rbfiles = &.{"mrbgems/mruby-data/test/data.rb"},
    },
    Mgem{
        .name = "mruby_dir",
        .srcs = &.{"mrbgems/mruby-dir/src/dir.c"},
        .includePaths = &.{"mrbgems/mruby-dir/src"},
        .rbfiles = &.{"mrbgems/mruby-dir/mrblib/dir.rb"},
        .test_srcs = &.{"mrbgems/mruby-dir/test/dirtest.c"},
        .test_rbfiles = &.{"mrbgems/mruby-dir/test/dir.rb"},
    },
    Mgem{
        .name = "mruby_enum_chain",
        .rbfiles = &.{"mrbgems/mruby-enum-chain/mrblib/chain.rb"},
        .test_rbfiles = &.{"mrbgems/mruby-enum-chain/test/enum_chain.rb"},
        .dependencies = &.{
            "mruby_fiber",
            //
            "mruby_enumerator",
        },
    },
    Mgem{
        .name = "mruby_enum_ext",
        .rbfiles = &.{"mrbgems/mruby-enum-ext/mrblib/enum.rb"},
        .test_rbfiles = &.{"mrbgems/mruby-enum-ext/test/enum.rb"},
    },
    Mgem{
        .name = "mruby_enum_lazy",
        .rbfiles = &.{"mrbgems/mruby-enum-lazy/mrblib/lazy.rb"},
        .test_rbfiles = &.{"mrbgems/mruby-enum-lazy/test/lazy.rb"},
        .dependencies = &.{
            "mruby_fiber",
            //
            "mruby_enumerator",
            "mruby_enum_ext",
        },
    },
    Mgem{
        .name = "mruby_enumerator",
        .rbfiles = &.{"mrbgems/mruby-enumerator/mrblib/enumerator.rb"},
        .test_rbfiles = &.{"mrbgems/mruby-enumerator/test/enumerator.rb"},
        .dependencies = &.{"mruby_fiber"},
    },
    Mgem{
        .name = "mruby_errno",
        .rbfiles = &.{"mrbgems/mruby-errno/mrblib/errno.rb"},
        .srcs = &.{"mrbgems/mruby-errno/src/errno.c"},
        .test_rbfiles = &.{"mrbgems/mruby-errno/test/errno.rb"},
    },
    Mgem{
        .name = "mruby_error",
        .srcs = &.{"mrbgems/mruby-error/src/exception.c"},
        .test_rbfiles = &.{"mrbgems/mruby-error/test/exception.rb"},
        .test_srcs = &.{"mrbgems/mruby-error/test/exception.c"},
    },
    Mgem{
        .name = "mruby_eval",
        .srcs = &.{"mrbgems/mruby-eval/src/eval.c"},
        .test_rbfiles = &.{"mrbgems/mruby-eval/test/eval.rb"},
        .dependencies = &.{
            "mruby_binding",
            // test deps
            // "mruby_method",
            // "mruby_metaprog",
        },
    },
    Mgem{
        .name = "mruby_exit",
        .srcs = &.{"mrbgems/mruby-exit/src/mruby-exit.c"},
        .test_rbfiles = &.{}, // TODO: missing spec coverage
    },
    Mgem{
        .name = "mruby_fiber",
        .srcs = &.{"mrbgems/mruby-fiber/src/fiber.c"},
        .test_rbfiles = &.{"mrbgems/mruby-fiber/test/fiber.rb"},
    },
    Mgem{
        .name = "mruby_hash_ext",
        .srcs = &.{"mrbgems/mruby-hash-ext/src/hash-ext.c"},
        .rbfiles = &.{"mrbgems/mruby-hash-ext/mrblib/hash.rb"},
        .test_rbfiles = &.{"mrbgems/mruby-hash-ext/test/hash.rb"},
        .dependencies = &.{"mruby_array_ext"},
    },
    Mgem{
        .name = "mruby_io",
        .srcs = &.{
            "mrbgems/mruby-io/src/file.c",
            "mrbgems/mruby-io/src/file_test.c",
            "mrbgems/mruby-io/src/io.c",
            "mrbgems/mruby-io/src/mruby_io_gem.c",
        },
        .includePaths = &.{"mrbgems/mruby-io/include"},
        .rbfiles = &.{
            "mrbgems/mruby-io/mrblib/file.rb",
            "mrbgems/mruby-io/mrblib/file_constants.rb",
            "mrbgems/mruby-io/mrblib/io.rb",
            "mrbgems/mruby-io/mrblib/kernel.rb",
        },
        .test_srcs = &.{"mrbgems/mruby-io/test/mruby_io_test.c"},
        .test_rbfiles = &.{
            "mrbgems/mruby-io/test/file.rb",
            "mrbgems/mruby-io/test/file_test.rb",
            "mrbgems/mruby-io/test/io.rb",
        },
        // test dep
        .dependencies = &.{"mruby_time"},
    },
    Mgem{
        .name = "mruby_kernel_ext",
        .srcs = &.{"mrbgems/mruby-kernel-ext/src/kernel.c"},
        .test_rbfiles = &.{"mrbgems/mruby-kernel-ext/test/kernel.rb"},
    },
    Mgem{
        .name = "mruby_math",
        .srcs = &.{"mrbgems/mruby-math/src/math.c"},
        .test_rbfiles = &.{"mrbgems/mruby-math/test/math.rb"},
    },
    Mgem{
        .name = "mruby_metaprog",
        .srcs = &.{"mrbgems/mruby-metaprog/src/metaprog.c"},
        .test_rbfiles = &.{"mrbgems/mruby-metaprog/test/metaprog.rb"},
    },
    Mgem{
        .name = "mruby_method",
        .srcs = &.{"mrbgems/mruby-method/src/method.c"},
        .rbfiles = &.{"mrbgems/mruby-method/mrblib/method.rb"},
        .test_rbfiles = &.{"mrbgems/mruby-method/test/method.rb"},
        .dependencies = &.{"mruby_proc_ext"},
    },
    Mgem{
        .name = "mruby_numeric_ext",
        .srcs = &.{"mrbgems/mruby-numeric-ext/src/numeric_ext.c"},
        .rbfiles = &.{"mrbgems/mruby-numeric-ext/mrblib/numeric_ext.rb"},
        .test_rbfiles = &.{"mrbgems/mruby-numeric-ext/test/numeric.rb"},
    },
    Mgem{
        .name = "mruby_object_ext",
        .srcs = &.{"mrbgems/mruby-object-ext/src/object.c"},
        .rbfiles = &.{"mrbgems/mruby-object-ext/mrblib/object.rb"},
        .test_rbfiles = &.{"mrbgems/mruby-object-ext/test/object.rb"},
    },
    Mgem{
        .name = "mruby_objectspace",
        .srcs = &.{"mrbgems/mruby-objectspace/src/mruby_objectspace.c"},
        .test_rbfiles = &.{"mrbgems/mruby-objectspace/test/objectspace.rb"},
    },
    Mgem{
        .name = "mruby_os_memsize",
        .srcs = &.{"mrbgems/mruby-os-memsize/src/memsize.c"},
        .test_rbfiles = &.{"mrbgems/mruby-os-memsize/test/memsize.rb"},
        .dependencies = &.{
            "mruby_objectspace",
            // test dep
            "mruby_metaprog",
            "mruby_method",
            "mruby_fiber",
        },
    },
    Mgem{
        .name = "mruby_pack",
        .srcs = &.{"mrbgems/mruby-pack/src/pack.c"},
        .test_rbfiles = &.{"mrbgems/mruby-pack/test/pack.rb"},
    },
    Mgem{
        .name = "mruby_print",
        .srcs = &.{"mrbgems/mruby-print/src/print.c"},
        .rbfiles = &.{"mrbgems/mruby-print/mrblib/print.rb"},
        .test_rbfiles = &.{}, // TODO: spec coverage
    },
    Mgem{
        .name = "mruby_proc_binding",
        .srcs = &.{"mrbgems/mruby-proc-binding/src/proc-binding.c"},
        .test_rbfiles = &.{"mrbgems/mruby-proc-binding/test/proc-binding.rb"},
        .test_srcs = &.{"mrbgems/mruby-proc-binding/test/proc-binding.c"},
        .dependencies = &.{
            "mruby_proc_ext",
            "mruby_binding",
            // test dep
            "mruby_eval",
            // "mruby_compiler",
        },
    },
    Mgem{
        .name = "mruby_proc_ext",
        .srcs = &.{"mrbgems/mruby-proc-ext/src/proc.c"},
        .includePaths = &.{},
        .rbfiles = &.{"mrbgems/mruby-proc-ext/mrblib/proc.rb"},
        .test_srcs = &.{"mrbgems/mruby-proc-ext/test/proc.c"},
        .test_rbfiles = &.{"mrbgems/mruby-proc-ext/test/proc.rb"},
    },
    Mgem{
        .name = "mruby_random",
        .srcs = &.{"mrbgems/mruby-random/src/random.c"},
        .test_rbfiles = &.{"mrbgems/mruby-random/test/random.rb"},
    },
    Mgem{
        .name = "mruby_range_ext",
        .srcs = &.{"mrbgems/mruby-range-ext/src/range.c"},
        .rbfiles = &.{"mrbgems/mruby-range-ext/mrblib/range.rb"},
        .test_rbfiles = &.{"mrbgems/mruby-range-ext/test/range.rb"},
    },
    Mgem{
        .name = "mruby_rational",
        .srcs = &.{"mrbgems/mruby-rational/src/rational.c"},
        .rbfiles = &.{"mrbgems/mruby-rational/mrblib/rational.rb"},
        .test_rbfiles = &.{"mrbgems/mruby-rational/test/rational.rb"},
        .dependencies = &.{
            "mruby_math",
            "mruby_complex",
        },
        .defines = &.{"MRB_USE_RATIONAL"},
    },
    Mgem{
        .name = "mruby_set",
        .rbfiles = &.{"mrbgems/mruby-set/mrblib/set.rb"},
        .test_rbfiles = &.{"mrbgems/mruby-set/test/set.rb"},
        .dependencies = &.{
            "mruby_hash_ext",
            "mruby_fiber",
            "mruby_enumerator",
        },
    },
    Mgem{
        .name = "mruby_sleep",
        .srcs = &.{"mrbgems/mruby-sleep/src/sleep.c"},
        .test_rbfiles = &.{"mrbgems/mruby-sleep/test/sleep_test.rb"},
    },
    Mgem{
        .name = "mruby_socket",
        .rbfiles = &.{"mrbgems/mruby-socket/mrblib/socket.rb"},
        .srcs = &.{"mrbgems/mruby-socket/src/socket.c"},
        .test_rbfiles = &.{
            "mrbgems/mruby-socket/test/addrinfo.rb",
            "mrbgems/mruby-socket/test/basicsocket.rb",
            "mrbgems/mruby-socket/test/ipsocket.rb",
            "mrbgems/mruby-socket/test/socket.rb",
            "mrbgems/mruby-socket/test/tcpsocket.rb",
            "mrbgems/mruby-socket/test/udpsocket.rb",
            "mrbgems/mruby-socket/test/unix.rb",
        },
        .test_srcs = &.{
            "mrbgems/mruby-socket/test/sockettest.c",
        },
        .dependencies = &.{
            "mruby_io",
            "mruby_error",
            // TODO: might need to link wsock32 on windows
        },
    },
    Mgem{
        .name = "mruby_sprintf",
        .srcs = &.{"mrbgems/mruby-sprintf/src/sprintf.c"},
        .rbfiles = &.{"mrbgems/mruby-sprintf/mrblib/string.rb"},
        .test_rbfiles = &.{"mrbgems/mruby-sprintf/test/sprintf.rb"},
    },
    Mgem{
        .name = "mruby_string_ext",
        .srcs = &.{"mrbgems/mruby-string-ext/src/string.c"},
        .rbfiles = &.{"mrbgems/mruby-string-ext/mrblib/string.rb"},
        .test_rbfiles = &.{"mrbgems/mruby-string-ext/test/string.rb"},
    },
    Mgem{
        .name = "mruby_struct",
        .srcs = &.{"mrbgems/mruby-struct/src/struct.c"},
        .rbfiles = &.{"mrbgems/mruby-struct/mrblib/struct.rb"},
        .test_rbfiles = &.{"mrbgems/mruby-struct/test/struct.rb"},
    },
    Mgem{
        .name = "mruby_symbol_ext",
        .srcs = &.{"mrbgems/mruby-symbol-ext/src/symbol.c"},
        .rbfiles = &.{"mrbgems/mruby-symbol-ext/mrblib/symbol.rb"},
        .test_rbfiles = &.{"mrbgems/mruby-symbol-ext/test/symbol.rb"},
    },
    Mgem{
        .name = "mruby_test",
        .srcs = &.{},
        .includePaths = &.{},
        .rbfiles = &.{},
        .test_rbfiles = &.{
            "test/t/argumenterror.rb",
            "test/t/array.rb",
            "test/t/basicobject.rb",
            "test/t/bs_block.rb",
            "test/t/bs_literal.rb",
            "test/t/class.rb",
            "test/t/comparable.rb",
            "test/t/ensure.rb",
            "test/t/enumerable.rb",
            "test/t/exception.rb",
            "test/t/false.rb",
            "test/t/float.rb",
            "test/t/gc.rb",
            "test/t/hash.rb",
            "test/t/indexerror.rb",
            "test/t/integer.rb",
            "test/t/iterations.rb",
            "test/t/kernel.rb",
            "test/t/lang.rb",
            "test/t/literals.rb",
            "test/t/localjumperror.rb",
            "test/t/methods.rb",
            "test/t/module.rb",
            "test/t/nameerror.rb",
            "test/t/nil.rb",
            "test/t/nomethoderror.rb",
            "test/t/numeric.rb",
            "test/t/object.rb",
            "test/t/proc.rb",
            "test/t/rangeerror.rb",
            "test/t/regexperror.rb",
            "test/t/runtimeerror.rb",
            "test/t/standarderror.rb",
            "test/t/string.rb",
            "test/t/superclass.rb",
            "test/t/symbol.rb",
            "test/t/syntax.rb",
            "test/t/true.rb",
            "test/t/typeerror.rb",
            "test/t/unicode.rb",
            "test/t/vformat.rb",
        },
    },
    Mgem{
        .name = "mruby_test_inline_struct",
        .test_srcs = &.{"mrbgems/mruby-test-inline-struct/test/inline.c"},
        .test_rbfiles = &.{"mrbgems/mruby-test-inline-struct/test/inline.rb"},
    },
    Mgem{
        .name = "mruby_time",
        .srcs = &.{"mrbgems/mruby-time/src/time.c"},
        .includePaths = &.{"mrbgems/mruby-time/include"},
        .rbfiles = &.{},
        .test_rbfiles = &.{"mrbgems/mruby-time/test/time.rb"},
    },
    Mgem{
        .name = "mruby_toplevel_ext",
        .rbfiles = &.{"mrbgems/mruby-toplevel-ext/mrblib/toplevel.rb"},
        .test_rbfiles = &.{"mrbgems/mruby-toplevel-ext/test/toplevel.rb"},
    },
};

const mruby_core_c_files = [_][]const u8{
    "src/allocf.c",
    "src/array.c",
    "src/backtrace.c",
    "src/cdump.c",
    "src/class.c",
    "src/codedump.c",
    "src/debug.c",
    "src/dump.c",
    "src/enum.c",
    "src/error.c",
    "src/etc.c",
    "src/fmt_fp.c",
    "src/gc.c",
    "src/hash.c",
    "src/init.c",
    "src/kernel.c",
    "src/load.c",
    "src/mempool.c",
    "src/numeric.c",
    "src/numops.c",
    "src/object.c",
    "src/print.c",
    "src/proc.c",
    "src/range.c",
    "src/readfloat.c",
    "src/readint.c",
    "src/readnum.c",
    "src/state.c",
    "src/string.c",
    "src/symbol.c",
    "src/variable.c",
    "src/version.c",
    "src/vm.c",
};
