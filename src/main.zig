const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const utils = @import("utils.zig");
const Matrix = utils.Matrix;

const PNGFile = @import("PNGFile.zig");
const rl = @import("raylib");


const win_w: u32 = 800;
const win_h: u32 = 800;


fn drawImage(mat: Matrix(rl.Color)) void {
    const rect_size: u32 = @divExact(win_w, @as(u32, @intCast(mat.w)));
    for (0..mat.h) |i| {
        for (0..mat.w) |j| {
            const color = mat.data[i*mat.w + j];
            
            rl.drawRectangle(
                @intCast(j*rect_size),
                @intCast(i*rect_size),
                @intCast(rect_size),
                @intCast(rect_size),
                color
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
    const png_file: PNGFile = try PNGFile.init(&alloc, file);
    std.debug.print("\n\nThis is the total image:\n", .{});
    png_file.img_data.print();
    std.debug.print("\n\n", .{});

    rl.initWindow(win_w,win_h, file_name);
    defer rl.closeWindow();
    
    while(!rl.windowShouldClose()) {
        if (rl.isKeyPressed(rl.KeyboardKey.q)) break;
        
        rl.beginDrawing();
        drawImage(png_file.img_data);
        rl.endDrawing();
    }
}
