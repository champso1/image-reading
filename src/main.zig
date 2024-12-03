const std = @import("std");
const stdout = std.io.getStdOut().writer();
const Allocator = std.mem.Allocator;
const utils = @import("utils.zig");
const ArrayList = std.ArrayList;


const GenericError = error{
    GenericError,
};


const PNGFile = struct{
    /// this is what should be the first eight bytes of the file
    pub const PNG_SIGNATURE: [8]u8 = [_]u8{
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A
    };

    
    pub const MAX_FILE_LEN: comptime_int = 4096;

    
    buf: []u8,
    ptr: usize,
    alloc: *const Allocator,

    img_w: u32,
    img_h: u32,
    bit_depth: u8,
    color_type: u8,

    img_data: ?[]u8,

    
    
    const ReadError = error{
        BufferSizeTooLarge,
        InvalidSignature,
        InvalidHeader
    };

    const PNGError = error{
        MissingIDATChunk,
    };


    
    fn read(self: *PNGFile, buf: []u8) ReadError!usize {
        if (buf.len + self.ptr >= self.buf.len) {
            return ReadError.BufferSizeTooLarge;
        }
        const end = self.ptr + buf.len;

        @memcpy(buf[0..], self.buf[self.ptr..end]);

        self.ptr = end;
        return buf.len;
    }

    const Reader = std.io.Reader(*PNGFile, ReadError, read);
    pub fn reader(self: *PNGFile) Reader {
        return .{.context = self};
    }


    pub fn init(alloc: *const Allocator, file_path: []const u8) !PNGFile {
        var buf: [MAX_FILE_LEN]u8 = undefined;
        const file: std.fs.File = try std.fs.cwd().openFile(file_path, .{});
        const bytes_read = try file.reader().read(buf[0..]);
        
        // before we return a png file, we want to go ahead and get the signature and IHDR chunk data
        const signature: []const u8 = buf[0..8];
        if (!std.mem.eql(u8, signature, PNG_SIGNATURE[0..])) {
            std.debug.print("[ERROR] Invalid PNG signature. Found {X:0>2} but expected {X:0>2}\n", .{
                signature, PNG_SIGNATURE[0..],
            });
            return ReadError.InvalidSignature;
        }

        const all_ihdr_data: []const u8 = buf[8..33]; //size of IHDR is 25
        const ihdr_size: u32 = utils.byteArrToInt(all_ihdr_data[0..4].*);
        if (ihdr_size != 13) {
            std.debug.print("[ERROR] Invalid header size. Expected 13 but found {d}\n", .{ihdr_size});
            return ReadError.InvalidHeader;
        }
        const ihdr_name: []const u8 = all_ihdr_data[4..8];
        if (!std.mem.eql(u8, ihdr_name, "IHDR")) {
            std.debug.print("[ERROR] Invalid header name. Expected \"IHDR\" but found {s}\n", .{ihdr_name});
            return ReadError.InvalidHeader;
        }
        
        // at this point we assume its okay.
        const ihdr_data: []const u8 = all_ihdr_data[8..21];
        const img_w: u32 = utils.byteArrToInt(ihdr_data[0..4].*);
        const img_h: u32 = utils.byteArrToInt(ihdr_data[4..8].*);
        const bit_depth: u8 = ihdr_data[8];
        const color_type: u8 = ihdr_data[9];

        // still check CRC though
        const ihdr_crc: u32 = utils.byteArrToInt(all_ihdr_data[21..25].*);
        const crc_calculated: u32 = utils.crc32(all_ihdr_data[4..21]);
        if (ihdr_crc != crc_calculated) {
            std.debug.print("[ERROR] Header CRC invalid. Expected 0x{X} but found 0x{X}.\n", .{crc_calculated, ihdr_crc});
            return ReadError.InvalidHeader;
        }
        

        return .{
            .buf = buf[0..bytes_read],
            .ptr = 33,
            .alloc = alloc,
            .img_w = img_w,
            .img_h = img_h,
            .bit_depth = bit_depth,
            .color_type = color_type,
            .img_data = null // just at first
        };
    }

    pub const Chunk = struct{
        chunk_len: u32,
        chunk_name: [4]u8 = undefined,
        chunk_data: []const u8,

        pub const MAX_DATA_LEN: usize = 1028;

        const ChunkError = error{
            InvalidCRC,
            InvalidChunkSize,
        };

        pub fn print(self: *const Chunk) void {
            std.debug.print("----- CHUNK INFO -----\n", .{});
            std.debug.print("Chunk name: {s}\nChunk size: {d}\nChunk data: {X:0>2}\n", .{
                self.chunk_name[0..], self.chunk_len, self.chunk_data,
            });
            std.debug.print("----------------------\n", .{});
        }
    };

    
    pub fn readChunk(self: *PNGFile) !Chunk {
        var png_reader = self.reader();
        
        var chunk_len_arr: [4]u8 = undefined;
        _ = try png_reader.read(chunk_len_arr[0..]);
        const chunk_len: usize = @intCast(utils.byteArrToInt(chunk_len_arr));

        var chunk_name: [4]u8 = undefined;
        _ = try png_reader.read(chunk_name[0..]);
        
        const chunk_data: []u8 = try self.alloc.alloc(u8, chunk_len);
        _ = try png_reader.read(chunk_data);

        
        // TODO: compute CRC (just copy dat shit bruv)
        var crc_arr: [4]u8 = undefined;
        _ = try png_reader.read(crc_arr[0..]);
        const crc: u32 = utils.byteArrToInt(crc_arr);

        const all_chunk_data: []u8 = try std.mem.concat(self.alloc.*, u8, &[_][]const u8{chunk_name[0..], chunk_data});
        const crc_calculated: u32 = utils.crc32(all_chunk_data);

        if (crc != crc_calculated) {
            std.debug.print("[ERROR] CRC for chunk {s} was invalid. Expected: {d}, but found {d}\n", .{chunk_name[0..], crc_calculated, crc});
            return Chunk.ChunkError.InvalidCRC;
        }

        return Chunk{
            .chunk_len = @intCast(chunk_len),
            .chunk_name = chunk_name,
            .chunk_data = chunk_data,
        };
    }



    pub fn getIDATData(self: *PNGFile) !?Chunk {
        // check if it has already been found
        if (self.img_data) |_| {
            std.debug.print("[WARNING] IDAT chunk has already been located. Why are you calling `getIDATData()` multiple times?\n", .{});
            return null;
        }
        
        // we just grab the idat chunk
        var chunk: Chunk = undefined;

        // TODO: in principle, this should always find an IDAT chunk
        // since any valid PNG must have at least one
        // but it may be nice to have error handling
        var i: u8 = 0;
        while (true) : (i += 1) { 
            chunk = try self.readChunk();
            if (std.mem.eql(u8, chunk.chunk_name[0..], "IDAT")) break;
            if (i > 254) {
                std.debug.print("[ERROR] IDAT chunk not found!\n", .{});
                return PNGError.MissingIDATChunk;
            }
        } else {
        }

        // TODO: see notes
        // now we need to decompress
        var compressed_data_stream = std.io.fixedBufferStream(chunk.chunk_data);
        var arraylist = ArrayList(u8).init(self.alloc.*);
        try std.compress.zlib.decompress(compressed_data_stream.reader(), arraylist.writer());

        // TODO: maybe we want to keep the original, compressed data?
        // i guess we could just recompress it if we want but
        // TODO: this is a fucking mess!
        const chunk_data: []u8 = try arraylist.toOwnedSlice();
        chunk.chunk_data = chunk_data;
        self.img_data = chunk_data;
        return chunk;
    }



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

    
    pub fn toMatrix(self: *PNGFile) ![]Color {
        if (self.img_data) |_| {} else {
            std.debug.print("[ERROR] Missing IDAT data. Perhaps you need to get the chunk data?\n", .{});
            return PNGError.MissingIDATChunk;
        }
        
        var buf = try self.alloc.alloc(Color, self.img_w*self.img_h);

        for (0..self.img_h) |i| {
            const filter_byte: u8 = self.img_data.?[i*(self.img_w+1)];
            switch (filter_byte) {
                0 => {
                    // filter byte=0 means that there is no filtering,
                    // i.e. recon(x) = orig(x)
                    for (1..self.img_w+1) |j| {
                        const x: u8 = self.img_data.?[i*(self.img_w+1) + j];
                        buf[i*self.img_w + (j-1)] = Color.grayscale(x);
                    }
                },
                1 => {
                    // filter byte=1 means
                    // recon(x) = filt(x) + recon(a)
                    // a is the byte before,
                    // a is 0 for the first byte
                    var a: u8 = 0;
                    for (1..self.img_w+1) |j| {
                        const x: u8 = self.img_data.?[i*(self.img_w+1) + j] + a;
                        buf[i*self.img_w + (j-1)] = Color.grayscale(x);
                        a = x;
                    }
                },
                else => {// TODO: make a png with a differnet filter byte}
                }
            }
        }
        
        return buf;
    }

};






const rl = @cImport({
    @cInclude("raylib.h");
});


const win_w: c_int = 400;
const win_h: c_int = 400;


fn drawMatrix(matrix: []PNGFile.Color, img_w: u32, img_h: u32) void {
    // this is a little silly...
    const rect_size: u32 = @divExact(@as(u32, @intCast(win_w)), img_w); // 100
    
    for (0..img_h) |i| {
        for (0..img_w) |j| {
            rl.DrawRectangle(
                @intCast(j*rect_size), @intCast(i*rect_size), @intCast(rect_size), @intCast(rect_size), matrix[i*img_w + j].toRaylibColor()
            );
        }
    }
}


pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    
    var png_file: PNGFile = try PNGFile.init(&alloc, "./res/pic_grayscale_big.png");
    _ = try png_file.getIDATData();
    const img_matrix: []PNGFile.Color = try png_file.toMatrix();

    rl.InitWindow(win_w,win_h, "Test");
    defer rl.CloseWindow();
    
    while(!rl.WindowShouldClose()) {
        if (rl.IsKeyPressed(rl.KEY_Q)) break;
        
        rl.BeginDrawing();
        drawMatrix(img_matrix, png_file.img_w, png_file.img_h);
        rl.EndDrawing();
    }
}
