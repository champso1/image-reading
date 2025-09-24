const std = @import("std");
const stdout = std.io.getStdOut().writer();
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const utils = @import("utils.zig");
const Matrix = utils.Matrix;
const Color = utils.Color;

const PNGFile = @import("PNGFile.zig");
const rl = @import("raylib");


const win_w: c_int = 800;
const win_h: c_int = 800;


fn drawImage(mat: Matrix(Color)) void {
    // this is a little silly...
    const rect_size: u32 = @divExact(@as(u32, @intCast(win_w)), @as(u32, @intCast(mat.w)));
    for (0..mat.h) |i| {
        for (0..mat.w) |j| {
            rl.DrawRectangle(
                @intCast(j*rect_size),
                @intCast(i*rect_size),
                @intCast(rect_size),
                @intCast(rect_size),
                mat.data[i*mat.w + j].toRaylibColor()
            );
        }
    }
}


pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const args = try std.process.argsAlloc(alloc);

    if (args.len != 2) @panic("Incorrect number of arguments");

    const file_name: [:0]const u8 = args[1];
    const file: std.fs.File = try std.fs.cwd().openFile(file_name, .{});
    var png_file: PNGFile = try PNGFile.init(&alloc, file);
    (try png_file.img_data.get(16, 0)).print();

    rl.InitWindow(win_w,win_h, file_name);
    defer rl.CloseWindow();
    
    while(!rl.WindowShouldClose()) {
        if (rl.IsKeyPressed(rl.KEY_Q)) break;
        
        rl.BeginDrawing();
        drawImage(png_file.img_data);
        rl.EndDrawing();
    }
}
