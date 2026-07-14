const std = @import("std");
const assert = std.debug.assert;

pub const Pair = struct {
    value: f32,
    count: u32,

    pub fn lessThan(context: void, a: Pair, b: Pair) bool {
        _ = context;
        return a.value < b.value;
    }

    pub fn countLessThan(context: void, a: Pair, b: Pair) bool {
        _ = context;
        return a.count < b.count;
    }
};

const StatReport = struct {
    mean: f32,
    mode: f32,
    mode_count: u32,
    median: f32,
    lower_quart: f32,
    upper_quart: f32,
    std_dev: f32,
    min: f32,
    max: f32,
};

pub fn basicStatReport(data: []const f32) StatReport {
    var sum: f32 = data[0];
    var max_run: usize = 1;
    var run_start: usize = 0;
    var mode_ = data[0];
    const epsilon = @sqrt(std.math.floatEps(f32));
    for (1..data.len) |i| {
        const x = data[i];
        sum += x;
        if (!std.math.approxEqRel(f32, x, data[i - 1], epsilon)) {
            if (i - run_start > max_run) {
                max_run = i - run_start;
                mode_ = data[i - 1];
            }
            run_start = i;
        }
    }

    const mean = sum / intToF32(data.len);
    const median_ = median(data);
    const mid = data.len / 2;
    const lower_quart = if (data.len % 2 == 1) median(data[0 .. mid + 1]) else median(data[0..mid]);
    const upper_quart = median(data[mid..]);

    var diff_sum: f32 = 0;
    for (data) |x| {
        const diff = mean - x;
        diff_sum += diff * diff;
    }
    const std_dev: f32 = @sqrt(diff_sum / intToF32(data.len));

    return .{
        .mean = mean,
        .mode = mode_,
        .mode_count = @intCast(max_run),
        .median = median_,
        .std_dev = std_dev,
        .lower_quart = lower_quart,
        .upper_quart = upper_quart,
        .min = data[0],
        .max = data[data.len - 1],
    };
}

fn intToF32(int: anytype) f32 {
    return @floatFromInt(int);
}

pub fn arithimeticMean(data: []const f32) f32 {
    assert(data.len > 0);
    var sum: f32 = 0;
    for (data) |x| sum += x;
    return sum / data.len;
}

pub fn median(data: []const f32) f32 {
    assert(data.len > 0);
    const mid = data.len / 2;
    if (data.len % 2 == 1)
        return data[mid];

    return (data[mid] + data[mid -| 1]) / 2;
}

pub fn mode(data: []const f32) f32 {
    assert(data.len > 0);
    var max_run: u32 = 1;
    var run_start: u32 = 0;
    var max_run_value = data[0];
    const epsilon = @sqrt(std.math.floatEps(f32));
    for (data[1..], 0..) |x, i| {
        if (!std.math.approxEqRel(f32, x, data[i - 1], epsilon)) {
            if (i - run_start > max_run) {
                max_run = i - run_start;
                max_run_value = data[i - 1];
            }
            run_start = i;
        }
    }
    return max_run_value;
}
