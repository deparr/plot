const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;

const Options = struct {
    const Colors = struct {
        const _reset = "\x1b[m";
        const red = "\x1b[31m";
        const green = "\x1b[32m";
        const yellow = "\x1b[33m";
        const blue = "\x1b[34m";
        const purple = "\x1b[35m";
        const cyan = "\x1b[36m";
        const fg = "\x1b[37m";

        const bold = "\x1b[1m";
    };
};

fn optKind(a: []const u8) enum { short, long, positional } {
    if (std.mem.startsWith(u8, a, "--")) return .long;
    if (std.mem.startsWith(u8, a, "-")) return .short;
    return .positional;
}

const Pair = struct {
    value: i32,
    count: u32,

    pub fn lessThan(context: void, a: Pair, b: Pair) bool {
        _ = context;
        return a.value < b.value;
    }
};

const Plot = struct {
    kind: enum {
        line,
        dot,
        histogram,
    } = .dot,
    arena: std.mem.Allocator,
    data: std.ArrayListUnmanaged(Pair) = .empty,
    symbol: enum {
        x,
        X,
        star,
        pound,
        equals,
        o,
        O,
        full_block,
        half_sextant,
    } = .full_block,

    fn findEntry(self: *const Plot, val: i32) ?*Pair {
        for (self.data.items, 0..) |p, i|
            if (p.value == val) return &self.data.items[i];
        return null;
    }

    fn maxCount(self: *const Plot) u32 {
        var count_max: u32 = 0;
        for (self.data.items) |dp| {
            if (dp.count > count_max)
                count_max = dp.count;
        }

        return count_max;
    }

    fn maxValue(self: *const Plot) i32 {
        var value_max: i32 = std.math.minInt(i32);
        for (self.data.items) |dp| {
            if (dp.value > value_max)
                value_max = dp.value;
        }

        return value_max;
    }

    fn maxValueWidth(self: *const Plot) u32 {
        var width: u32 = 0;
        for (self.data.items) |dp| {
            const item_width = intWidth(dp.value);
            if (item_width > width)
                width = item_width;
        }

        return width;
    }

    const symbols = [_][]const u8{
        "x",
        "X",
        "*",
        "#",
        "=",
        "+",
        "o",
        "O",
        "█",
        "🬋",
    };

    fn getSymbol(self: *const Plot) []const u8 {
        return symbols[@intFromEnum(self.symbol)];
    }
};

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const gpa, const is_debug = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    var plot = Plot{ .arena = allocator };
    try plot.data.ensureTotalCapacity(allocator, 80);

    var stdin = std.io.getStdIn().reader();
    var linebuf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(linebuf[0..]);

    while (true) {
        stdin.streamUntilDelimiter(fbs.writer(), '\n', fbs.buffer.len) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        const full_line = fbs.getWritten();
        const line = std.mem.trim(u8, full_line, &std.ascii.whitespace);

        const val = try std.fmt.parseInt(i32, line, 10);
        if (plot.findEntry(val)) |entry| {
            entry.count += 1;
        } else {
            plot.data.appendAssumeCapacity(.{ .value = val, .count = 1 });
        }

        fbs.reset();
    }

    std.sort.pdq(Pair, plot.data.items, {}, Pair.lessThan);

    // todo assume 140 width (2 cells per column + padding at beg/end)
    const plot_width = plot.data.items.len * 2 + 2;
    assert(plot_width < 140);
    const count_max = plot.maxCount();
    const value_width_max = plot.maxValueWidth();
    const top_border = count_max + 1;

    const stdout = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout);

    const symbol = plot.getSymbol();
    for (0..top_border) |i| {
        const pos = top_border - i;
        if (pos % 5 == 0) {
            try bw.writer().print("{d: >2}|", .{pos});
        } else {
            _ = try bw.write("  |");
        }
        for (plot.data.items) |dp| {
            for (0..value_width_max) |_| {
                try bw.writer().writeByte(' ');
            }
            if (pos <= dp.count) {
                try bw.writer().writeAll(symbol);
            } else {
                try bw.writer().writeByte(' ');
            }
        }
        _ = try bw.write("\n");
    }

    _ = try bw.write("  ");
    for (0..(plot.data.items.len + 1) * value_width_max) |_| {
        _ = try bw.write("-");
    }
    _ = try bw.write("\n   ");

    var value_buf: [10]u8 = .{' '} ** 10;
    assert(value_width_max < value_buf.len);
    for (plot.data.items) |dp| {
        @memset(&value_buf, ' ');
        const space_offset = value_width_max - intWidth(dp.value) + 1;
        _ = try std.fmt.bufPrint(value_buf[space_offset..], "{d}", .{dp.value});
        try bw.writer().writeAll(value_buf[0..value_width_max + 1]);
    }
    _ = try bw.write("\n");

    try bw.flush();
}

fn intWidth(i: i32) u32 {
    var width: u32 = 1;
    if (i < 0) width += 1;
    var ai = @abs(i);
    while (ai >= 10) {
        ai /= 10;
        width += 1;
    }

    return width;
}
