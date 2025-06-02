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

//--

const Foo = struct {
    // NOTE: `@sizeOf(Foo)` must be non-zero for `mrb_malloc`.
    data: u8 = 0,

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
    const new_memory = mruby.mrb_malloc_simple(mrb, @sizeOf(Foo)) orelse {
        @panic("mrb_malloc_simple returned NULL");
    };

    const foo: *Foo = @ptrCast(@alignCast(new_memory));
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
