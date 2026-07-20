const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const flag = @import("flag");
const stats = @import("stats.zig");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const pixel_code_ttf = @embedFile("./fonts/PixelCode.ttf");


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
    render: enum {
        text,
        image
    } = if (builtin.os.tag == .windows) .text else .image,
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
    at,

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
        "@",
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
    num_points: u32 = 0,
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

const Command = enum {
    dot,
    line,
    histogram,
    stats,
    box,
};

const DataSet = union(Plot.Kind) {
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

    var flags = Flags{};
    var commands: []const []const u8 = &[_][]const u8{ "dot" };
    {
        const args_raw = try init.minimal.args.toSlice(arena);
        const parsed = try flag.Parser(Flags).parse(arena, args_raw, &flags, .{});
        if (parsed.positional.len > 0)
            commands = parsed.positional;
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
        plot.num_points += 1;

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

    plot.data = pairs;
    if (flags.render == .text) {
        try renderTextPlot(stdout, plot);
    } else {
        const width = 600;
        const height = 500;
        var surface = try z2d.Surface.init(.image_surface_rgba, init.gpa, width, height);
        defer surface.deinit(init.gpa);
        var canvas = z2d.Context.init(io, init.gpa, &surface);
        try canvas.setFontToBuffer(pixel_code_ttf);
        defer canvas.deinit();
        try renderImagePlot(&canvas, plot);
        const pix_buf: []const u8 = @ptrCast(surface.image_surface_rgba.buf);
        const png_buf: []const u8 = try png.encodeAlloc(init.gpa, pix_buf, 600, 500);
        defer init.gpa.free(png_buf);
        try stdout.writeAll(png_buf);

        // try writer.print("\x1b]1337;File=size={d};inline=1:", .{ png_buf.len });
        // try std.base64.standard.Encoder.encodeWriter(writer, png_buf);
        // try writer.writeAll("\x1b\\");
        try stdout.flush();
    }
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

fn renderTextPlot(writer: *Io.Writer, plot: Plot) !void {
    const plot_width = plot.data.items.len * 2 + 2;
    assert(plot_width < 140);
    const count_max = plot.maxCount();
    const value_width_max = plot.maxValueWidth();
    const top_border = count_max + 1;

    const symbol = plot.symbol.string();
    for (0..top_border) |i| {
        const pos = top_border - i;
        if (pos % 5 == 0) {
            try writer.print("{d: >2}├", .{pos});
        } else {
            try writer.writeAll("  │");
        }
        for (plot.data.items) |dp| {
            for (0..value_width_max) |_| {
                try writer.writeByte(' ');
            }
            if (pos <= dp.count) {
                try writer.writeAll(symbol);
            } else {
                try writer.writeByte(' ');
            }
        }
        try writer.writeByte('\n');
    }

    try writer.writeAll("  └");
    for (0..(1 + plot.data.items.len * (value_width_max + 1))) |_| {
        try writer.writeAll("─");
    }
    try writer.writeAll("\n   ");

    var value_buf: [10]u8 = @splat(' ');
    assert(value_width_max < value_buf.len);
    for (plot.data.items) |dp| {
        @memset(&value_buf, ' ');
        const space_offset = value_width_max - intWidth(dp.value) + 1;
        _ = try std.fmt.bufPrint(value_buf[space_offset..], "{d}", .{dp.value});
        try writer.writeAll(value_buf[0 .. value_width_max + 1]);
    }
    try writer.writeByte('\n');

    try writer.flush();
}

const z2d = @import("z2d");
const png = @import("png.zig");

fn renderImagePlot( c: *z2d.Context, plot: Plot) !void {
    const normalized_max_height: f64 = 0.8;
    c.setAntiAliasingMode(.none);
    try fillRect(c, 0, 0, 600, 500, .{ .rgb = .{1, 1, 1}});
    c.resetPath();

    try fillRect(c, 29, 30, 2, 440, .{ .rgb = .{ 0, 0, 0 } });
    try fillRect(c, 29, 470, 560, 2, .{ .rgb = .{ 0, 0, 0 } });
    c.resetPath();

    const count_max: f64 = @floatFromInt(plot.maxCount());
    const max_height_px: f64 = (500 - 60) * normalized_max_height;
    const num_bars: f64 = @floatFromInt(plot.data.items.len);
    const bar_sep_px: f64 = 4.0;
    const bar_width: f64 = (538 - num_bars * bar_sep_px) / num_bars;

    for (plot.data.items, 1..) |dp, i| {
        const i_f: f64 = @floatFromInt(i);
        const count: f64 = @floatFromInt(dp.count);
        const x = 31.0 + bar_sep_px * i_f + bar_width * (i_f - 1);
        const h = max_height_px * count / count_max;
        const y = 500.0 - (30 + h);
        try fillRect(c, x, y, bar_width, h, .{ .rgb = .{ 0.14, 0.67, 0.95 } });
    }

    c.setSourceToPixel(.fromColor(.{ .rgb = .{ 0.1, 0.1, 0.1 }}));
    c.setFontSize(36);
    try c.showText("plot title", 240, 30);
    c.setFontSize(27);
    try c.showText("12345678", 32, 472);
}

fn fillRect(c: *z2d.Context, x: f64, y: f64, w: f64, h: f64, color: z2d.Color.InitArgs) !void {
    c.setSourceToPixel(.fromColor(color));
    try c.moveTo(x, y);
    try c.lineTo(x + w, y);
    try c.lineTo(x + w, y + h);
    try c.lineTo(x, y + h);
    try c.closePath();
    try c.fill();
}
