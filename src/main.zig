const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const flag = @import("flag");
const stats = @import("stats.zig");
const Io = std.Io;

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

const Flags = struct {
    symbol: Symbol = .star,
    input: []const u8 = "",
    output: []const u8 = "",
    delimiter: []const u8 = ",",
};

const Pair = stats.Pair;

const Symbol = enum {
    x,
    X,
    star,
    pound,
    equals,
    plus,
    o,
    O,
    full_block,
    half_sextant,
    braille,

    const strings = [_][]const u8{
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
        "⠃",
    };

    pub fn string(self: Symbol) []const u8 {
        return strings[@intFromEnum(self)];
    }

    comptime {
        if (@typeInfo(Symbol).@"enum".fields.len != strings.len)
            @compileError("Symbol variants out of sync with string reprs");
    }
};

const Plot = struct {
    arena: std.mem.Allocator,
    data: std.ArrayListUnmanaged(Pair) = .empty,
    symbol: Symbol,

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

    pub const Kind = enum {
        line,
        dot,
        histogram,
        stats,
    };
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const log = std.log.default;

    if (builtin.os.tag == .windows) {
        var handle = std.os.windows.CONSOLE.USER_IO.SET_CP(.Output, 65001);
        const status = try handle.operate(io, null);
        if (status != .SUCCESS) {
            log.warn("unable to set code page to UTF-8, unicode likely won't display correctly", .{});
        }
    }

    const args_raw = try init.minimal.args.toSlice(arena);
    const args = try flag.Parser(Flags).parse(args_raw, .{ .arena = arena, .collect_positional = true });
    const flags = args.flags;
    const commands = args.positional;
    if (commands.len == 0) {
        log.err("need at least one plot kind to make", .{});
        std.process.exit(1);
    }

    const plot_kind = std.meta.stringToEnum(Plot.Kind, commands[0]) orelse {
        log.err("unknown plot command: {s}", .{commands[0]});
        std.process.exit(1);
    };

    var plot = Plot{ .symbol = flags.symbol, .arena = arena };
    var data = try std.ArrayList(f32).initCapacity(arena, 80);

    var stdin_buf: [256]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(io, &stdin_buf);
    var stdin = &stdin_reader.interface;
    var line_buf: [256]u8 = undefined;
    var fbs = Io.Writer.fixed(&line_buf);

    while (true) {
        const line_len = try stdin.streamDelimiterEnding(&fbs, '\n');
        if (line_len == 0) break;

        const full_line = fbs.buffered();
        const line = std.mem.trim(u8, full_line, &std.ascii.whitespace);
        if (std.mem.startsWith(u8, line, "@@@")) break;

        const val = try std.fmt.parseFloat(f32, line);
        try data.append(arena, val);

        _ = fbs.consumeAll();
        stdin.toss(1);
    }

    std.sort.pdq(f32, data.items, {}, std.sort.asc(f32));

    const report = stats.basicStatReport(data.items);

    var stdout_writer = Io.File.stdout().writer(io, &line_buf);
    var stdout = &stdout_writer.interface;

    if (plot_kind == .stats) {
        try stdout.print(
            \\ mean: {d:.2} | 𝜎: {d:.2}
            \\ median: {d:.2}
            \\ Q1: {d:.2} | Q3: {d:.2}
            \\ mode: {d} ({d})
            \\ min: {d} max: {d}
            \\
        ,
            .{
                report.mean,
                report.std_dev,
                report.median,
                report.lower_quart,
                report.upper_quart,
                report.mode,
                report.mode_count,
                report.min,
                report.max,
            },
        );
        try stdout.flush();

        return;
    }

    var pairs = try std.ArrayList(stats.Pair).initCapacity(arena, 80);
    for (data.items) |x| {
        if (hasValue(pairs.items, x)) |pair| {
            pair.count += 1;
        } else {
            try pairs.append(arena, .{ .value = x, .count = 1 });
        }
    }

    // todo assume 140 width (2 cells per column + padding at beg/end)
    plot.data = pairs;
    const plot_width = plot.data.items.len * 2 + 2;
    assert(plot_width < 140);
    const count_max = plot.maxCount();
    const value_width_max = plot.maxValueWidth();
    const top_border = count_max + 1;

    const symbol = plot.symbol.string();
    for (0..top_border) |i| {
        const pos = top_border - i;
        if (pos % 5 == 0) {
            try stdout.print("{d: >2}├", .{pos});
        } else {
            try stdout.writeAll("  │");
        }
        for (plot.data.items) |dp| {
            for (0..value_width_max) |_| {
                try stdout.writeByte(' ');
            }
            if (pos <= dp.count) {
                try stdout.writeAll(symbol);
            } else {
                try stdout.writeByte(' ');
            }
        }
        try stdout.writeByte('\n');
    }

    try stdout.writeAll("  └");
    for (0..(1 + plot.data.items.len * (value_width_max + 1))) |_| {
        try stdout.writeAll("─");
    }
    try stdout.writeAll("\n   ");

    var value_buf: [10]u8 = @splat(' ');
    assert(value_width_max < value_buf.len);
    for (plot.data.items) |dp| {
        @memset(&value_buf, ' ');
        const space_offset = value_width_max - intWidth(dp.value) + 1;
        _ = try std.fmt.bufPrint(value_buf[space_offset..], "{d}", .{dp.value});
        try stdout.writeAll(value_buf[0 .. value_width_max + 1]);
    }
    try stdout.writeByte('\n');

    try stdout.flush();
}

fn intWidth(i: f32) u32 {
    var width: u32 = 1;
    if (i < 0) width += 1;
    var ai = @abs(i);
    while (ai >= 10) {
        ai /= 10;
        width += 1;
    }

    return width;
}

fn hasValue(pairs: []Pair, value: f32) ?*Pair {
    const epsilon = @sqrt(std.math.floatEps(f32));
    for (pairs) |*pair| {
        if (std.math.approxEqRel(f32, pair.value, value, epsilon))
            return pair;
    }
    return null;
}
