const std = @import("std");
const stdout = std.io.getStdOut().writer();
const Allocator = std.mem.Allocator;
const utils = @import("utils.zig");
const ArrayList = std.ArrayList;



const PNGFile = struct{
    /// this is what should be the first eight bytes of the file
    pub const PNG_SIGNATURE: [8]u8 = [_]u8{
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A
    };

    // in case the allocator's state gets changed, we store a pointer to the main one
    // also there's only one in general, so we don't want it copied around i guess
    alloc: *const Allocator,

    // this is all that is necessary to store from the header
    // other things are either largely irrelevant or always 0
    img_w: u32,
    img_h: u32,
    bit_depth: u8,
    color_type: u8,


    
    // this is the uncompressed/inflated image data
    // and also reconstructing the scanlines
    // can be directly used to rendering
    img_data: []Color,

    // optional as maybe there are no auxilliary chunks?
    aux_chunks: ?[]Chunk,


    pub const Color = struct{
        r: u8,
        g: u8,
        b: u8,
        a: u8,

        pub fn toRaylibColor(self: Color) rl.Color {
            return rl.Color{
                .r = self.r, .g = self.g, .b = self.b, .a = self.a,
            };
        }

        // manually making the struct is annoying...
        pub fn grayscale(x: u8) Color {
            return Color{
                .r = x, .g = x, .b = x, .a = 255,
            };
        }
    };

    

    pub const PNGError = error{
        InvalidSignature,
        InvalidHeader,
        InvalidChunkCRC,
    };


    const MAX_FILE_SIZE: comptime_int = 8*1000*1000;
    

    pub fn init(alloc: *const Allocator, file_handle: std.fs.File) !PNGFile {
        const file_reader: std.fs.File.Reader = file_handle.reader();

        var idx: usize = 0;
        const file_contents: []u8 = try file_reader.readAllAlloc(alloc.*, MAX_FILE_SIZE);

        const signature: []u8 = getBytes(file_contents, &idx, 8);
        if (!std.mem.eql(u8, signature, PNG_SIGNATURE[0..])) {
            std.debug.print("[ERROR] Invalid PNG signature. Found {X:0>2} but expected {X:0>2}\n", .{
                signature, PNG_SIGNATURE[0..],
            });
            return PNGError.InvalidSignature;
        }

        const all_ihdr_data: []u8 = getBytes(file_contents, &idx, 25); //including size, name, data, and crc
        const ihdr_size: u32 = utils.byteArrToInt(all_ihdr_data[0..4].*);
        if (ihdr_size != 13) {
            std.debug.print("[ERROR] Invalid header size. Expected 13 but found {d}\n", .{ihdr_size});
            return PNGError.InvalidHeader;
        }
        const ihdr_name: []const u8 = all_ihdr_data[4..8];
        if (!std.mem.eql(u8, ihdr_name, "IHDR")) {
            std.debug.print("[ERROR] Invalid header name. Expected \"IHDR\" but found {s}\n", .{ihdr_name});
            return PNGError.InvalidHeader;
        }
        
        // at this point we assume everything is okay
        const ihdr_data: []const u8 = all_ihdr_data[8..21];
        const img_w: u32 = utils.byteArrToInt(ihdr_data[0..4].*);
        const img_h: u32 = utils.byteArrToInt(ihdr_data[4..8].*);
        const bit_depth: u8 = ihdr_data[8];
        const color_type: u8 = ihdr_data[9];
        // again, the rest of the bytes we don't care about (yet)

        
        const ihdr_crc: u32 = utils.byteArrToInt(all_ihdr_data[21..25].*);
        const ihdr_crc_calculated: u32 = utils.crc32(all_ihdr_data[4..21]);
        if (ihdr_crc != ihdr_crc_calculated) {
            std.debug.print("[ERROR] Header CRC invalid. Expected 0x{X} but found 0x{X}.\n", .{ihdr_crc_calculated, ihdr_crc});
            return PNGError.InvalidHeader;
        }


        // after this, the rest of the chunks are ancillary chunks and IDAT chunk(s) in no particular order
        // so we just loop through all of the chunks until we hit the IEND chunk,
        // parsing IDAT data if it's an IDAT chunk,
        // otherwise sticking it in the optional aux_chunk arraylist
        var aux_chunk_buf: ?[]Chunk = null;
        var num_aux_chunks: usize = 0;
        var img_data_bytes: []u8 = undefined;
        var img_data: []Color = undefined;

        // we are safe to do this because it is guaranteed to have at least two more chunks (IDAT and IEND)
        var chunk_size_arr: []u8 = getBytes(file_contents, &idx, 4);
        var chunk_size: u32 = utils.byteArrToInt(chunk_size_arr[0..4].*); //idk why index?
        var chunk_name: []u8 = getBytes(file_contents, &idx, 4); // name
        while (!std.mem.eql(u8, chunk_name, "IEND")) {
            const chunk_data: []u8 = getBytes(file_contents, &idx, chunk_size);
            // crc is universal, do this either way
            
            const chunk_crc_arr: []u8 = getBytes(file_contents, &idx, 4);
            const chunk_crc: u32 = utils.byteArrToInt(chunk_crc_arr[0..4].*);
            const all_chunk_data: []u8 = try std.mem.concat(alloc.*, u8, &[_][]const u8{chunk_name, chunk_data});
            const crc_calculated: u32 = utils.crc32(all_chunk_data);

            if (chunk_crc != crc_calculated) {
                std.debug.print("[ERROR] {s} chunk CRC is invalid.\n[INFO] Expected: 0x{X}, but got 0x{X}\n", .{chunk_name, crc_calculated, chunk_crc});
                return PNGError.InvalidChunkCRC;
            }
            
            if (std.mem.eql(u8, chunk_name, "IDAT")) {
                var compressed_data_stream = std.io.fixedBufferStream(chunk_data);
                var arraylist = ArrayList(u8).init(alloc.*);
                try std.compress.zlib.decompress(compressed_data_stream.reader(), arraylist.writer());

                img_data_bytes = try arraylist.toOwnedSlice();
                img_data = try toMatrix(alloc, img_data_bytes, color_type, img_w, img_h);
                
            } else {
                if (aux_chunk_buf) |_| {} else {
                    aux_chunk_buf = try alloc.alloc(Chunk, 16);
                }

                aux_chunk_buf.?[num_aux_chunks] = Chunk{
                    .chunk_size = chunk_size,
                    .chunk_name = chunk_name[0..4].*,
                    .chunk_data = chunk_data,
                };
                num_aux_chunks += 1;
            }
            

            // also safe to do this since guaranteed to have at least one chunk (IEND)
            chunk_size_arr = getBytes(file_contents, &idx, 4);
            chunk_size = utils.byteArrToInt(chunk_size_arr[0..4].*);
            chunk_name = getBytes(file_contents, &idx, 4);
        }

        return .{
            .alloc = alloc,
            
            .img_w = img_w,
            .img_h = img_h,
            .bit_depth = bit_depth,
            .color_type = color_type,
            
            .img_data = img_data,

            .aux_chunks = aux_chunk_buf,
            
        };
    }

    fn getBytes(arr: []u8, idx: *usize, num_bytes: usize) []u8 {
        defer idx.* += num_bytes;
        return arr[idx.*..idx.* + num_bytes];
    }



    fn toMatrix(alloc: *const Allocator, idat_data: []const u8, color_type: u8, img_w: u32, img_h: u32) ![]Color {
        var matrix: []Color = try alloc.alloc(Color, img_w*img_h);

        // TODO: stop being lazy!
        _ = color_type;

        for (0..img_h) |i| {
            const filter_byte: u8 = idat_data[i*(img_w+1)];
            switch (filter_byte) {
                0 => {
                    // filter byte=0 means that there is no filtering,
                    // i.e. recon(x) = orig(x)
                    for (1..img_w+1) |j| {
                        const x: u8 = idat_data[i*(img_w+1) + j];
                        matrix[i*img_w + (j-1)] = Color.grayscale(x);
                    }
                },
                1 => {
                    // filter byte=1 means
                    // recon(x) = filt(x) + recon(a)
                    // a is the byte before,
                    // a is 0 for the first byte
                    var a: u8 = 0;
                    for (1..img_w+1) |j| {
                        const x: u8 = idat_data[i*(img_w+1) + j] + a;
                        matrix[i*img_w + (j-1)] = Color.grayscale(x);
                        a = x;
                    }
                },
                else => {} // TODO: make a png with a differnet filter byte
            }
        }

        return matrix;
    }
    

    pub const Chunk = struct{
        chunk_size: u32,
        chunk_name: [4]u8 = undefined,
        chunk_data: []const u8,

        pub fn print(self: *const Chunk) void {
            std.debug.print("----- CHUNK INFO -----\n", .{});
            std.debug.print("Chunk name: {s}\nChunk size: {d}\nChunk data: {X:0>2}\n", .{
                self.chunk_name[0..], self.chunk_size, self.chunk_data,
            });
            std.debug.print("----------------------\n", .{});
        }
    };
};




const rl = @cImport({
    @cInclude("raylib.h");
});


const win_w: c_int = 400;
const win_h: c_int = 400;


fn drawImage(png_file: PNGFile) void {
    // this is a little silly...
    const rect_size: u32 = @divExact(@as(u32, @intCast(win_w)), png_file.img_w); //
    
    for (0..png_file.img_h) |i| {
        for (0..png_file.img_w) |j| {
            rl.DrawRectangle(
                @intCast(j*rect_size), @intCast(i*rect_size), @intCast(rect_size), @intCast(rect_size), png_file.img_data[i*png_file.img_w + j].toRaylibColor()
            );
        }
    }
}


pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const file: std.fs.File = try std.fs.cwd().openFile("./res/pic_grayscale_big.png", .{});
    const png_file: PNGFile = try PNGFile.init(&alloc, file);

    rl.InitWindow(win_w,win_h, "Test");
    defer rl.CloseWindow();
    
    while(!rl.WindowShouldClose()) {
        if (rl.IsKeyPressed(rl.KEY_Q)) break;
        
        rl.BeginDrawing();
        drawImage(png_file);
        rl.EndDrawing();
    }
}
