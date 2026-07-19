//! A *very* scuffed png encoder
//! Assumes input data is rgba8

const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const assert = std.debug.assert;

pub fn encodeAlloc(gpa: mem.Allocator, data: []const u8, width: u32, height: u32) ![]u8 {
    var allocating = Io.Writer.Allocating.init(gpa);
    errdefer allocating.deinit();
    try encodeStream(&allocating.writer, data, width, height);
    return allocating.toOwnedSlice();
}

pub fn encodeStream(writer: *Io.Writer, data: []const u8, width: u32, height: u32) !void {
    assert(width != 0 and height != 0);
    assert(width <= 1200);

    try writePngSignature(writer);
    try writePngIHDR(writer, width, height);
    try writePngIDAT(writer, width, height, data);
    try writePngIEND(writer);
}

fn writePngSignature(writer: *Io.Writer) !void {
    const signature = "\x89PNG\x0D\x0A\x1A\x0A";
    try writer.writeAll(signature);
}


fn writePngIHDR(writer: *Io.Writer, width: u32, height: u32) !void {
    var width_buf: [4]u8 = @splat(0);
    var height_buf: [4]u8 = @splat(0);
    mem.writeInt(u32, &width_buf, width, .big);
    mem.writeInt(u32, &height_buf, height, .big);
    const color_type = 0x6;
    const compression = 0x00;
    const filter = 0x00;
    const interlaced = 0x00;
    const bits_per_chan = 0x8;
    return writePngChunk(
        writer,
        "IHDR".*,
        &(width_buf ++
            height_buf ++
            [_]u8{bits_per_chan} ++
            [_]u8{ color_type, compression, filter, interlaced }),
    );
}

fn writePngIDAT(writer: *Io.Writer, width: u32, height: u32, data: []const u8) !void {
    const idat_buf_len = 16384; // this limits the size of our png
    const flate = std.compress.flate;
    const scanline_buffer_len = 1200 * 4 + 1; // limits png width and size

    var zlib_buffer: [std.compress.flate.max_window_len] u8 = undefined;
    var idat_buffer: [idat_buf_len]u8 = undefined;

    var idat_writer = Io.Writer.fixed(&idat_buffer);

    var zlib_stream = try flate.Compress.init(
        &idat_writer,
        &zlib_buffer,
        .zlib,
        flate.Compress.Options.default,
    );

    const row_byte_width = width * 4;
    // be super lazy and just store a whole row on the stack
    for (0..height) |row| {
        var scanline_buffer: [scanline_buffer_len]u8 = @splat(0);
        const scanline_row = scanline_buffer[0..row_byte_width + 1];
        const sl_begin = row * row_byte_width;
        const sl_end = sl_begin + row_byte_width;
        @memcpy(scanline_row[1..], data[sl_begin..sl_end]);

        try zlib_stream.writer.writeAll(scanline_row);
    }

    try zlib_stream.finish();

    return writePngChunk(
        writer,
        "IDAT".*,
        idat_writer.buffered(),
    );
}

fn writePngIEND(writer: *Io.Writer) !void {
    return writePngChunk(writer, "IEND".*, &.{});
}

fn writePngChunk(writer: *Io.Writer, chunk_type: [4]u8, data: []const u8) !void {
    const len: u32 = @intCast(data.len);
    const crc = pngChunkCrc(chunk_type, data);

    try writer.writeInt(u32, len, .big);
    try writer.writeAll(&chunk_type);
    try writer.writeAll(data);
    return writer.writeInt(u32, crc, .big);
}

fn pngChunkCrc(chunk_type: [4]u8, data: []const u8) u32 {
    var crc = std.hash.Crc32.init();
    crc.update(chunk_type[0..]);
    crc.update(data);
    return crc.final();
}
