const std = @import("std");
const rl = @cImport({
    @cInclude("raylib.h");
});
const Allocator = std.mem.Allocator;
const CRC32IEEE = std.hash.Crc32;
const ArrayList = std.ArrayList;


const PNG_SIGNATURE = &[_]u8{ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };
const IHDR_SIZE: usize = 13;



// predefine CRC values on startup
const CRC32_POLYNOMIAL: u32 = 0xEDB88320;
var crc32_table: [256]u32 = undefined;
fn computeCRC32Table() void {
    for (0..256) |i| {
        var crc: u32 = @as(u32, @intCast(i));
        for (0..8) |j| {
            _ = j;
            if ((crc & 1) != 0) {
                crc = (crc >> 1) ^ CRC32_POLYNOMIAL;
            } else {
                crc = crc >> 1;
            }
        }
        crc32_table[i] = crc;
    }
    
}

// assumes the CRC table has already been filled
fn crc32(data: []const u8) u32 {
    var crc: u32 = 0xFFFFFFFF;

    for (data) |x| {
        crc = crc32_table[(crc ^ x) & 0xFF] ^ (crc >> 8);
    }

    return ~crc;
}







// convertes an array of bytes to a 32-bit (unsigned) integer
// this is Big Endian, I believe, with the most significant byte first
fn byteArrToInt(byte_arr: []const u8) u32 {
    // this shouldn't be possible, so I don't want to do error stuff
    if (byte_arr.len != 4) {
        return 0;
    }
    // TODO: there has to be a better way to do this lmao
    const size: u32 = (
        (@as(u32, @intCast(byte_arr[0])) << 24) |
            (@as(u32, @intCast(byte_arr[1])) << 16) |
            (@as(u32, @intCast(byte_arr[2])) << 8) |
            (@as(u32, @intCast(byte_arr[3])))
    );
    return size;
}


// also keeps MSB first
fn intToByteArr(int: u32) [4]u8 {
    var arr = [_]u8{0, 0, 0, 0};

    arr[0] = @as(u8, @intCast((int >> 24) & 0xFF));
    arr[1] = @as(u8, @intCast((int >> 16) & 0xFF));
    arr[2] = @as(u8, @intCast((int >> 8) & 0xFF));
    arr[3] = @as(u8, @intCast(int & 0xFF));
    
    return arr;
}






// all critical chunks are handled independently,
// and there is no need to store their data in this way,
// so this is only for Auxilliary chunks
const AuxChunk = struct{
    name: []const u8,
    data: []const u8,

    const Self = @This();


    // list of auxilliary chunk names for printing
    pub const AuxChunkNames = &[_][]const u8{
        "TEXT", "PHYS", "TIME"
    };
    pub const AuxChunkFuncs = &[_]*const fn(*const AuxChunk) void {
        printTEXTChunk, printPHYSChunk, printTIMEChunk
    };

    pub fn init(chunk_name: []const u8, chunk_data: []const u8) ?AuxChunk {
        var is_valid_chunk: bool = false;
        for (AuxChunkNames) |aux_chunk_name| {
            if (std.mem.eql(u8, aux_chunk_name, chunk_name)) is_valid_chunk = true;
        }

        if (!is_valid_chunk) {
            std.debug.print("[INFO] {s} is not a supported chunk name.\n", .{chunk_name});
            return null;
        }

        return .{
            .name = chunk_name,
            .data = chunk_data,
        };
    }

    
    fn chunkNameToUpper(self: *const Self) [4]u8 {
        var chunk_name_upper: [4]u8 = [_]u8{0, 0, 0, 0};
        for (&chunk_name_upper, 0..) |*c, i| {
            c.* = std.ascii.toUpper(self.name[i]);
        }
        return chunk_name_upper;
    }


    // assumes the requested chunk is an auxilliary chunk
    // critical chunks are handled themsevles automatically
    pub fn printChunk(self: *const Self) void {
        const chunk_name_upper: [4]u8 = self.chunkNameToUpper();
        var i: u8 = 0;
        for (AuxChunkNames, 0..) |chunk_name, j| {
            if (std.mem.eql(u8, chunk_name, chunk_name_upper[0..])) {
                i = @as(u8, @intCast(j));
                break;
            }
        }
        return AuxChunkFuncs[i](self);
    }

    fn printTEXTChunk(self: *const Self) void {
        std.debug.print("----- TEXT Chunk -----\n", .{});
        std.debug.print("{s}\n", .{self.data});
        std.debug.print("----------------------\n", .{});
    }


    fn printPHYSChunk(self: *const Self) void {
        std.debug.print("----- PHYS Chunk -----\n", .{});
        std.debug.print("Pixels per Unit (X): {d}\nPixels Per Unit (Y): {d}\n", .{
            byteArrToInt(self.data[0..4]), byteArrToInt(self.data[4..8]),
        });
        
        if (self.data[8] == 1) {
            std.debug.print("Units: Meters\n", .{});
        }
        std.debug.print("----------------------\n", .{});
    }



    fn printTIMEChunk(self: *const Self) void {
        std.debug.print("----- TIME Chunk -----\n", .{});
        const year: u16 = (@as(u16, self.data[0]) << 8) | (@as(u16, self.data[1]));
        std.debug.print("Date created: {d}/{d}/{d} {d:0<2}:{d}:{d}\n", .{
            year, self.data[2], self.data[3],
            self.data[4], self.data[5], self.data[6],
        });
        std.debug.print("----------------------\n", .{});
    }
};





const IHDRData = struct{
    const Self = @This();
    
    width: u32,
    height: u32,
    bit_depth: u8,
    color_type: u8,
    compression_method: u8,
    filter_method: u8,
    interlace_method: u8,

    pub fn init(ihdr_data: []const u8) IHDRData {
        return .{
            .width = byteArrToInt(ihdr_data[0..4]),
            .height = byteArrToInt(ihdr_data[4..8]),
            .bit_depth = ihdr_data[8],
            .color_type = ihdr_data[9],
            .compression_method = ihdr_data[10],
            .filter_method = ihdr_data[11],
            .interlace_method = ihdr_data[12],
        };
    }

    pub fn print(self: *const Self) void {
        std.debug.print("Width: {d}\nHeight: {d}\n", .{self.width, self.height});
        std.debug.print("Bit Depth: {d}\n", .{self.bit_depth});
        std.debug.print("Color Type: {d}\n", .{self.color_type});
        std.debug.print("Compression Method: {d}\n", .{self.compression_method});
        std.debug.print("Filter Method: {d}\n", .{self.filter_method});
        std.debug.print("Interlace Method: {d}\n", .{self.interlace_method});
    }
};


const PLTEData = struct{
    pub const Palette = struct{
        r: u8,
        g: u8,
        b: u8
    };

    palettes: []const Palette,

    
    // assumes that the length is valid already
    pub fn init(allocator: *const Allocator, plte_data: []const u8) !PLTEData {
        var palettes_arraylist = ArrayList(Palette).init(allocator.*);
        
        var i: usize = 0;
        while (i < plte_data.len) : (i += 3) {
            try palettes_arraylist.append(Palette{
                .r = plte_data[i], .g = plte_data[i+1], .b = plte_data[i+2]
            });
        }

        return .{
            .palettes = try palettes_arraylist.toOwnedSlice(),
        };
    }
};



const IDATData = struct{
    const Self = @This();
    
    decompressed_data: []const u8,

    pub fn init(allocator: *const Allocator, compressed_data: []const u8) !IDATData {
        var compressed_data_stream = std.io.fixedBufferStream(compressed_data);
        var arraylist = ArrayList(u8).init(allocator.*);

        try std.compress.zlib.decompress(compressed_data_stream.reader(), arraylist.writer());

        return Self{
            .decompressed_data = try arraylist.toOwnedSlice(),
        };
    }
};




const PNG = struct{
    const Self = @This();

    allocator: *const Allocator,

    // critical chunks get their own data fields
    ihdr_data: IHDRData,
    plte_data: ?PLTEData, // since some color_types don't have this it is optional
    idat_data: IDATData,
    
    aux_chunks: []?AuxChunk, // these can be optional too; i don't have them all programmed in yet


    // groups various errors together
    const PNGError = error{
        InvalidSignature,
        InvalidChunkName,
        InvalidChunkCRC,
        EOF,
    };



    // basic idea:
    // check the signature, ensure it's a valid PNG
    // the loop through all the remaining chunks,
    // specially handling PLTE or IDAT chunks,
    // otherwise sticking it in the auxilliary chunks list
   
    pub fn init(file_path: []const u8, allocator: *const Allocator) !PNG {
        computeCRC32Table();
        
        const file: std.fs.File = try std.fs.cwd().openFile(file_path, .{});
        const file_reader: std.fs.File.Reader = file.reader();
        const all_data: []u8 = try file_reader.readAllAlloc(allocator.*, 8*1000);

        // internal "file pointer index" of sorts.
        var idx: usize = 0;
        
        const png_signature: []const u8 = getBytes(all_data, &idx, 8);
        if (!std.mem.eql(u8, PNG_SIGNATURE, png_signature)) {
            std.debug.print("[ERROR] Invalid PNG signature.\n\tExpected signature: {X:0>2}\n\tReceived: {X:0>2}\n", .{png_signature, all_data[0..8]});
            return PNGError.InvalidSignature;
        }

        // IHDR is next, we know the name and size so we can just skip it
        _ = getBytes(all_data, &idx, 8);
        const header_data: []const u8 = getBytes(all_data, &idx, IHDR_SIZE);
        const header_crc: []const u8 = getBytes(all_data, &idx, 4);

        // check the crc first before doing anything nutty
        const all_header_data = try std.mem.concat(allocator.*, u8, &[_][]const u8{"IHDR", header_data});
        const header_crc_calced: [4]u8 = intToByteArr(crc32(all_header_data));
        if (!std.mem.eql(u8, header_crc_calced[0..], header_crc)) {
            std.debug.print("[ERROR] Invalid header CRC. Expected: {X:0>2}\nReceived: {X:0>2}\n", .{header_crc_calced, header_crc});
            return PNGError.InvalidChunkCRC;
        }
        const ihdr_data: IHDRData = IHDRData.init(header_data);

        var plte_data: ?PLTEData = null;
        var idat_data: IDATData = undefined;
        var aux_chunks = ArrayList(?AuxChunk).init(allocator.*);


        // grab an initial chunk name and size; variable so they can continue to be set
        // and compared throughout the looping
        // we just want to peek the bytes here, since the loop will handle incrementing
        var chunk_size = byteArrToInt(peekBytes(all_data, idx, 4));
        var chunk_name: []const u8 = peekBytes(all_data, idx+4, 4);
        while (!std.mem.eql(u8, chunk_name, "IEND")) {
            chunk_size = byteArrToInt(getBytes(all_data, &idx, 4));
            chunk_name = getBytes(all_data, &idx, 4);
            const chunk_data = getBytes(all_data, &idx, chunk_size);
            const chunk_crc = getBytes(all_data, &idx, 4);

            // check the crc first:
            const all_chunk_data = try std.mem.concat(allocator.*, u8, &[_][]const u8{chunk_name, chunk_data});
            const chunk_crc_calced = &intToByteArr(crc32(all_chunk_data));
            if (!std.mem.eql(u8, chunk_crc_calced, chunk_crc)) {
                std.debug.print("[ERROR] Invalid chunk ({s}) CRC. Expected: {X:0>2}\nReceived: {X:0>2}\n", .{
                    chunk_name, chunk_crc_calced, chunk_crc
                });
                return PNGError.InvalidChunkCRC;
            }

            if (std.mem.eql(u8, chunk_name, "IEND")) {
                break;
            }
            else if (std.mem.eql(u8, chunk_name, "PLTE")) {
                plte_data = try PLTEData.init(allocator, chunk_data);
            } else if (std.mem.eql(u8, chunk_name, "IDAT")) {
                idat_data = try IDATData.init(allocator, chunk_data);
            } else {
                try aux_chunks.append(AuxChunk.init(chunk_name, chunk_data));
            }
        }

        return Self{
            .allocator = allocator,
            .ihdr_data = ihdr_data,
            .plte_data = plte_data,
            .idat_data = idat_data,
            .aux_chunks = try aux_chunks.toOwnedSlice(),
        };
        
    }


    // gets `num_bytes` from `data` and increments `idx` accordingly
    // mainly so i don't forget to increment the idx variable...
    fn getBytes(data: []const u8, idx: *usize, num_bytes: usize) []const u8 {
        defer idx.* += num_bytes;
        return data[idx.*..(idx.*+num_bytes)];
    }

    fn peekBytes(data: []const u8, idx: usize, num_bytes: usize) []const u8 {
        return data[idx..(idx+num_bytes)];
    }



    // essentially prints out the header information
    // with the option to print the auxilliary chunks
    pub fn stat(self: *const Self, print_aux_chunks: bool) void {
        std.debug.print("------- Image Stat -------\n", .{});
        self.ihdr_data.print();

        std.debug.print("Decompressed image data:\n", .{});
        std.debug.print("{X:0>2}\n\n", .{self.idat_data.decompressed_data});
        
        if (!print_aux_chunks) {
            return;
        }
        
        for (self.aux_chunks) |_aux_chunk| {
            if (_aux_chunk) |aux_chunk| {
                aux_chunk.printChunk();
            }
        }
        
    }


    // converts the IDAT data into a matrix
    // for grayscale
    pub fn toMatrix(self: *const Self) ![]u8{
        const data: []const u8 = self.idat_data.decompressed_data;
        const w: u32 = self.ihdr_data.width;
        const h: u32 = self.ihdr_data.height;
        var matrix: []u8 = try self.allocator.alloc(u8, w*h);
        // each scanline has a filter bit,
        // so there is an additional byte in each row
        for (0..h) |i| {
            const filter_byte: u8 = data[i*w];
            
            switch(filter_byte) {
                0 => {
                    for (1..w+1) |j| {
                        matrix[i*w + (j-1)] = data[i*w + j];
                    }
                },
                1 => {
                    var b: u8 = 0;
                    for (1..w+1) |j| {
                        matrix[i*w + (j-1)] = data[i*w + j] + b;
                        b = matrix[i*w + (j-1)];
                    }
                },
                else => {},
            }
        }

        return matrix;
    }
};


const win_w: c_int = 400;
const win_h: c_int = 400;


// man, working with raylib from Zig is a nightmare
// raysan using normal signed integers for positions and sizes is kinda nutty
fn drawImage(matrix: []const u8, img_w: u32, img_h: u32) void {
    const rect_size: u32 = @divExact(@as(u32, @intCast(win_w)), img_w); // should be the same for height as well
    for (0..img_h) |_i| {
        const i: u32 = @intCast(_i);
        for (0..img_w) |_j| {
            const j: u32 = @intCast(_j);
            const x: u8 = matrix[i*img_w + j];
            const color: rl.Color = rl.Color{.r = x, .g = x, .b = x, .a = 255};
            rl.DrawRectangle(
                @intCast(j*rect_size), @intCast(i*rect_size), @intCast(rect_size), @intCast(rect_size), color
            );
        }
    }
}


pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const file = try PNG.init("./res/pic2.png", &allocator);
    const matrix: []u8 = try file.toMatrix();

    rl.InitWindow(win_w, win_h, "New Window");
    defer rl.CloseWindow();

    while(!rl.WindowShouldClose()) {
        rl.BeginDrawing();
        
        rl.ClearBackground(rl.RAYWHITE);
        drawImage(matrix, file.ihdr_data.width, file.ihdr_data.height);
        
        rl.EndDrawing();
    }
}
