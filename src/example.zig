// SPDX-FileCopyrightText: © 2025 Mark Delk <jethrodaniel@gmail.com>
//
// SPDX-License-Identifier: MIT

const std = @import("std");
const builtin = @import("builtin");
const mruby = @import("mruby").c;

pub const std_options: std.Options = .{
    .log_level = .info,
};

pub fn main() !void {
    const logger = std.log.scoped(.@"example.zig");

    logger.info("Begin...", .{});

    logger.info("Creating mruby interpreter...", .{});
    const mrb: [*c]mruby.mrb_state = mruby.mrb_open();
    if (mrb == null) return error.mrb_open;
    defer _ = mruby.mrb_close(mrb);

    logger.info("Version/copyright...", .{});
    _ = mruby.mrb_show_version(mrb);
    _ = mruby.mrb_show_copyright(mrb);

    logger.info("Loading strings...", .{});
    _ = mruby.mrb_load_string(mrb, "def puts(str) = super(\"[MRUBY puts] #{str}\")");
    _ = mruby.mrb_load_string(mrb, "puts Time.now");

    logger.info("Loading a file...", .{});
    const fp: [*c]mruby.FILE = mruby.fopen("src/example.rb", "r");
    defer _ = mruby.fclose(fp);
    _ = mruby.mrb_load_file(mrb, fp);

    logger.info("Defining methods...", .{});
    _ = mruby.mrb_define_method(mrb, mrb.*.kernel_module, "string_method", string_method, 0);
    _ = mruby.mrb_load_string(mrb, "puts \"Kernel.string_method => #{Kernel.string_method}\"");

    _ = mruby.mrb_define_method(mrb, mrb.*.kernel_module, "int_method", int_method, 0);
    _ = mruby.mrb_load_string(mrb, "puts \"Kernel.int_method => #{Kernel.int_method}\"");

    _ = mruby.mrb_define_method(mrb, mrb.*.kernel_module, "nil_method", nil_method, 0);
    _ = mruby.mrb_load_string(mrb, "puts \"Kernel.nil_method => #{Kernel.nil_method.inspect}\"");

    logger.info("Defining classes...", .{});
    const foo = mruby.mrb_define_class(mrb, "Foo", mrb.*.object_class);
    _ = mruby.mrb_define_method(mrb, foo, "initialize", fooInitalize, 0);
    _ = mruby.mrb_define_method(mrb, foo, "one_arg", oneArg, 1);
    _ = mruby.mrb_define_method(mrb, foo, "two_args", twoArgs, 2);

    const foo_obj = mruby.mrb_obj_new(mrb, foo, 0, null);
    logger.info("Foo.new", .{});

    const one_arg_result = mruby.mrb_fixnum(
        mruby.mrb_funcall(mrb, foo_obj, "one_arg", 1, mruby.mrb_fixnum_value(41)),
    );
    logger.info("Foo.new.one_arg(41) => {d}", .{one_arg_result});

    const two_arg_result = mruby.mrb_fixnum(mruby.mrb_funcall(
        mrb,
        foo_obj,
        "two_args",
        2,
        mruby.mrb_fixnum_value(2),
        mruby.mrb_fixnum_value(3),
    ));
    logger.info("Foo.new.two_args(2, 3) => {d}", .{two_arg_result});

    logger.info("Defining constants...", .{});
    _ = mruby.mrb_define_const(
        mrb,
        foo,
        "SOME_CONSTANT",
        mruby.mrb_str_new_cstr(mrb, "tada"),
    );
    const constant_value = mruby.mrb_const_get(
        mrb,
        mruby.mrb_obj_value(foo),
        mruby.mrb_intern_cstr(mrb, "SOME_CONSTANT"),
    );

    const constant_cstr = mruby.mrb_string_cstr(mrb, constant_value);
    logger.info("Foo::SOME_CONSTANT => {s}", .{constant_cstr});

    logger.info("Exceptions...", .{});
    _ = mruby.mrb_load_string(mrb, "MissingContant");
    if (mrb.*.exc != null) {
        defer mrb.*.exc = null;
        mruby.mrb_print_error(mrb);

        const err = mruby.mrb_obj_value(mrb.*.exc);
        const detail = mruby.mrb_funcall(mrb, err, "inspect", 0);
        const str = mruby.mrb_string_cstr(mrb, detail);

        logger.err("Error => '{s}'", .{str});
    }

    {
        logger.info("Interpreter with a simple custom allocator...", .{});

        const custom_mrb: [*c]mruby.mrb_state = mruby.mrb_open_allocf(mrb_simple_allocf, null);
        if (custom_mrb == null) return error.mrb_open;
        defer _ = mruby.mrb_close(custom_mrb);

        _ = mruby.mrb_load_string(custom_mrb, "puts 'using a simple custom allocator!'");
    }

    {
        logger.info("Interpreter with a more complex custom allocator...", .{});

        var gpa = std.heap.GeneralPurposeAllocator(.{
            // .verbose_log = true,
            .enable_memory_limit = true,
        }){};
        gpa.setRequestedMemoryLimit(1024 * 700); // 700 KiB
        defer if (gpa.deinit() == .leak) @panic("found memory leaks");
        const allocator = gpa.allocator();

        // const allocator = std.heap.page_allocator;

        // Doesn't work, since fba is a bump pointer allocator
        // var buffer: [1024 * 1000]u8 = undefined;
        // var fba = std.heap.FixedBufferAllocator.init(&buffer);
        // const allocator = fba.allocator();

        // var realloc_map = std.AutoHashMap(usize, usize).init(std.heap.page_allocator);
        var realloc_map = std.AutoHashMap(usize, usize).init(allocator);
        defer realloc_map.deinit();

        const user_data = UserData{
            .allocator = &allocator,
            .realloc_map = &realloc_map,
        };

        const custom_mrb: [*c]mruby.mrb_state = mruby.mrb_open_allocf(mrb_complex_allocf, @as(?*anyopaque, @ptrCast(@constCast(&user_data))));
        if (custom_mrb == null) return error.mrb_open;
        defer _ = mruby.mrb_close(custom_mrb);

        logger.info("loaded interpreter...", .{});

        _ = mruby.mrb_load_string(custom_mrb, "puts 'using a more complex custom allocator!'");
        _ = mruby.mrb_load_string(custom_mrb, "$t = []; puts $t.inspect");
        _ = mruby.mrb_load_string(custom_mrb, "$t << :a; puts $t.inspect");
        _ = mruby.mrb_load_string(custom_mrb, "$t += [:a, :b, :c]; puts $t.inspect");

        if (custom_mrb.*.exc != null) mruby.mrb_print_error(custom_mrb);
    }

    logger.info("Done", .{});
}

fn string_method(mrb: [*c]mruby.mrb_state, self: mruby.mrb_value) callconv(.C) mruby.mrb_value {
    _ = self;
    return mruby.mrb_str_new_cstr(mrb, "example");
}

fn int_method(mrb: [*c]mruby.mrb_state, self: mruby.mrb_value) callconv(.C) mruby.mrb_value {
    _ = self;
    _ = mrb;
    return mruby.mrb_fixnum_value(42);
}

fn nil_method(mrb: [*c]mruby.mrb_state, self: mruby.mrb_value) callconv(.C) mruby.mrb_value {
    _ = self;
    _ = mrb;
    return mruby.mrb_nil_value();
}

fn mrb_simple_allocf(mrb: [*c]mruby.mrb_state, p: ?*anyopaque, size: usize, ud: ?*anyopaque) callconv(.C) ?*anyopaque {
    _ = mrb;
    _ = ud;

    if (size == 0) {
        if (p) |ptr| std.c.free(ptr);
        return null;
    } else {
        return std.c.realloc(p, size);
    }
}

const UserData = struct {
    allocator: *const std.mem.Allocator,
    realloc_map: *std.AutoHashMap(usize, usize),
};

// NOTE: trying to pass a custom allocator here is difficult, because we have
// to keep track of previous allocation sizes like realloc does internally.
fn mrb_complex_allocf(mrb: [*c]mruby.mrb_state, p: ?*anyopaque, size: usize, ud: ?*anyopaque) callconv(.C) ?*anyopaque {
    _ = mrb;

    const user_data = @as(*UserData, @ptrCast(@alignCast(ud))).*;
    const allocator = user_data.allocator;
    var realloc_map = @constCast(user_data.realloc_map);

    std.log.debug("-- realloc({x}, {d})", .{ @intFromPtr(p), size });

    if (size == 0) {
        if (p) |ptr| {
            if (realloc_map.getEntry(@intFromPtr(ptr))) |entry| {
                std.log.debug("  freeing existing pointer {x}", .{@intFromPtr(ptr)});

                const old_size = entry.value_ptr.*;
                const raw_ptr = entry.key_ptr.*;
                const slice = @as([*]u8, @ptrFromInt(raw_ptr))[0..old_size];

                allocator.free(slice);

                _ = realloc_map.remove(raw_ptr);

                return null;
            }
            std.log.err("  realloc({x}, {d}), but ptr is missing from realloc_map", .{ ptr, size });
            @panic("ptr missing from realloc map");
        }

        std.log.debug("  realloc({any}, {any}), seems invalid", .{ p, size });

        return null;
    } else {
        if (p) |ptr| {
            if (realloc_map.getEntry(@intFromPtr(ptr))) |entry| {
                const old_size = entry.value_ptr.*;
                const raw_ptr = entry.key_ptr.*;

                std.log.debug("  existing {x}, old_size: {d}", .{ raw_ptr, old_size });

                const slice = @as([*]u8, @ptrFromInt(raw_ptr))[0..old_size];
                const allocation = allocator.realloc(slice, size) catch @panic("oom");

                realloc_map.put(@intFromPtr(allocation.ptr), size) catch |err| {
                    std.log.err("{any}", .{err});
                    @panic("failed to update existing pointer size");
                };

                return allocation.ptr;
            }

            std.log.err("  realloc({x}, {d}), but ptr is missing from realloc_map", .{ ptr, size });
            @panic("ptr missing from realloc map");
        }

        const allocation = allocator.alloc(u8, size) catch @panic("oom");
        const ptr = allocation.ptr;

        realloc_map.put(@intFromPtr(ptr), size) catch |err| {
            std.log.err("{any}", .{err});
            @panic("failed to put new pointer into realloc_map");
        };
        std.log.debug("  new {x}", .{@intFromPtr(ptr)});

        return ptr;
    }
}

//--

const Foo = struct {
    const Self = @This();

    pub fn init() !Self {
        return Self{};
    }

    pub fn oneArg(self: *const Self, arg: i64) i64 {
        _ = self;

        return arg + 1;
    }

    pub fn twoArgs(self: *const Self, a: i64, b: i64) i64 {
        _ = self;

        return a + b;
    }

    pub fn close(self: *const Self) void {
        _ = self;
        return;
    }
};

const foo_data_type = mruby.mrb_data_type{
    .struct_name = "Foo",
    .dfree = fooFree,
};

fn fooFree(mrb: ?*mruby.mrb_state, ptr: ?*anyopaque) callconv(.C) void {
    const foo: Foo = @as(*Foo, @ptrCast(@alignCast(ptr))).*;
    foo.close();
    mruby.mrb_free(mrb, ptr);
}

fn fooInitalize(mrb: [*c]mruby.mrb_state, self: mruby.mrb_value) callconv(.C) mruby.mrb_value {
    const foo: *Foo = @ptrCast(@alignCast(mruby.mrb_realloc(mrb, null, @sizeOf(Foo))));
    const f = Foo.init() catch @panic("Foo.init()");
    foo.* = @as(*Foo, @ptrCast(@alignCast(@constCast(&f)))).*;

    const class = mruby.mrb_class_get(mrb, "Foo");
    const ptr: *anyopaque = @ptrCast(foo);

    const data_rdata = mruby.mrb_data_object_alloc(mrb, class, ptr, &foo_data_type);
    mruby.mrb_iv_set(mrb, self, mruby.mrb_intern_cstr(mrb, "@foo"), mruby.mrb_obj_value(data_rdata));

    return self;
}

fn oneArg(mrb: [*c]mruby.mrb_state, self: mruby.mrb_value) callconv(.C) mruby.mrb_value {
    const arg = mruby.mrb_get_arg1(mrb);
    const code = mruby.mrb_fixnum(arg);

    const foo_iv = mruby.mrb_iv_get(mrb, self, mruby.mrb_intern_cstr(mrb, "@foo"));
    const ptr = mruby.mrb_data_get_ptr(mrb, foo_iv, &foo_data_type);
    const foo = @as(*Foo, @ptrCast(@alignCast(ptr))).*;

    const result = foo.oneArg(code);

    return mruby.mrb_fixnum_value(result);
}

fn twoArgs(mrb: [*c]mruby.mrb_state, self: mruby.mrb_value) callconv(.C) mruby.mrb_value {
    var a: i64 = undefined;
    var b: i64 = undefined;

    // NOTE: mrb_int is either 64-bit, or 32-bit, depending on MRB_INT64/MRB_INT32.
    //   If we don't match exactly, we get weird runtime errors.
    _ = mruby.mrb_get_args(mrb, "ii", &a, &b);

    const foo_iv = mruby.mrb_iv_get(mrb, self, mruby.mrb_intern_cstr(mrb, "@foo"));
    const ptr = mruby.mrb_data_get_ptr(mrb, foo_iv, &foo_data_type);
    const foo = @as(*Foo, @ptrCast(@alignCast(ptr))).*;

    const result = foo.twoArgs(a, b);

    return mruby.mrb_fixnum_value(result);
}
