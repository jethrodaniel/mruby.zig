// SPDX-FileCopyrightText: © 2025 Mark Delk <jethrodaniel@gmail.com>
//
// SPDX-License-Identifier: MIT

const std = @import("std");

pub const std_options: std.Options = .{
    .log_level = .debug,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) @panic("found memory leaks");
    const allocator = gpa.allocator();

    // const logger = std.log.scoped(.@"fix-translation");

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 2) {
        std.log.err(
            \\Wrong number of arguments.
            \\  Usage: {s} {{translation.zig}} > {{output.zig}}
            \\
        , .{args[0]});
        std.process.exit(1);
    }
    const input_file = try std.fs.cwd().openFile(args[1], .{});
    errdefer input_file.close();

    const reader = input_file.reader();
    const writer = std.io.getStdOut().writer();

    var line_buf = std.ArrayList(u8).init(allocator);
    defer line_buf.deinit();

    while (reader.streamUntilDelimiter(line_buf.writer(), '\n', null)) {
        if (line_buf.getLastOrNull() == '\r') _ = line_buf.pop();
        defer line_buf.clearRetainingCapacity();

        const line = line_buf.items;
        // logger.debug("{s}", .{line});

        if (std.mem.eql(u8, line, "    gc: mrb_gc = @import(\"std\").mem.zeroes(mrb_gc),")) {
            _ = try writer.write("    gc: u128 = @import(\"std\").mem.zeroes([128]i1),");
        } else {
            _ = try writer.write(line);
        }

        _ = try writer.write("\n");
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => |e| return e,
    }
}
