const std = @import("std");
const z2d = @import("z2d");

const png = @import("png.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    const width = 200;

    var canvas = try z2d.Surface.init(.image_surface_rgba, gpa, width, width);
    defer canvas.deinit(gpa);
    var ctx = z2d.Context.init(io, gpa, &canvas);
    defer ctx.deinit();

    ctx.setSourceToPixel(.{ .rgba = .{ .r = 0xea, .g = 0x93, .b = 0xfe, .a = 0xff  } });
    try ctx.moveTo(width / 7, width / 7);
    try ctx.lineTo(width / 2, width / 3);
    try ctx.lineTo(6 * width / 7, width / 7);
    try ctx.lineTo(6 * width / 7, 6 * width / 7);
    try ctx.lineTo(width / 7, 6 * width / 7);
    try ctx.closePath();
    try ctx.fill();


    const buf: []u8 = @ptrCast(canvas.image_surface_rgba.buf);
    const png_buf = try png.encodeAlloc(gpa, buf, width, width);
    defer gpa.free(png_buf);
    const encoded_size = std.base64.standard.Encoder.calcSize(png_buf.len);
    const enc_buf = try gpa.alloc(u8, encoded_size);
    defer gpa.free(enc_buf);
    const encd = std.base64.standard.Encoder.encode(enc_buf, png_buf);

    var stdout_writer = std.Io.File.stdout().writer(io, &.{});
    const stdout = &stdout_writer.interface;
    // try stdout.print("\x1b_Gf=100,S={d};", .{ png_buf.len });
    try stdout.print("\x1b]1337;File=size={d};inline=1:", .{ png_buf.len });
    try stdout.writeAll(encd);
    try stdout.writeAll("\x1b\\");
}
