const std = @import("std");     
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const utils = @import("utils.zig");
const Matrix = utils.Matrix;
const Color = utils.Color;



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
img_data: Matrix(Color),



// optional as maybe there are no auxilliary chunks?
aux_chunks: ?[]Chunk,



pub const PNGError = error{
    InvalidSignature,
    InvalidHeader,
    InvalidChunkCRC,
};


/// completely arbitrary. I think this is 8MB?
const MAX_FILE_SIZE: comptime_int = 8*1000*1000;



/// Parses the signature and header of a png file, verifying it is valid
/// and storing information about the png file
/// then it parses the remaining chunk, storing ancillary chunks in a separate array
/// and decompressing the IDAT data.
pub fn init(alloc: *const Allocator, file_handle: std.fs.File) !Self {

    // this shoud allegedly read the file into the "file_contents" buffer...
    const stat = try file_handle.stat();
    const file_size = stat.size;
    const file_contents = try alloc.*.alloc(u8, @intCast(file_size));
    _ = try file_handle.readAll(file_contents);
    
    var idx: usize = 0;
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


    // after this, the rest of the chunks are ancillary chunks and IDAT chunk(s) in no partcular order
    // so we just loop through all of the chunks until we hit the IEND chunk,
    // parsing IDAT data if it's an IDAT chunk,
    // otherwise sticking it in the optional aux_chunk arraylist
    var aux_chunk_buf: ?[]Chunk = null;
    var num_aux_chunks: usize = 0;
    var img_data_bytes: []u8 = undefined;
    var img_data: Matrix(Color) = undefined;

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




/// Internal function to advance a buffer pointer and return the number of bytes requested
/// Mainly so I don't forget to increment the buffer pointer
fn getBytes(arr: []u8, idx: *usize, num_bytes: usize) []u8 {
    defer idx.* += num_bytes;
    return arr[idx.*..idx.* + num_bytes];
}




/// filter byte=0 means that there is no filtering,
/// i.e. recon(x) = filt(x)
fn filterLineNone(matrix: *Matrix(Color), line: []const u8, row: usize, fac: u8) Matrix(Color).MatrixError!void {
    std.debug.print("{d} ", .{row});
    const line_width: usize = matrix.w*fac;
    var idx_line: usize = 0;
    var idx_mat: usize = 0;
        
    while (idx_line < line_width) : ({
        idx_line += fac;
        idx_mat += 1;
    }) {
        const x: u8 = line[idx_line];
        var rgb: [3]u8 = [_]u8{x,x,x};
        
        for (1..fac) |i| {
            rgb[i] = line[idx_line+i];
        }

        const color: Color = Color{.r = rgb[0], .g = rgb[1], .b = rgb[2], .a = 255,};

        try matrix.set(row, idx_mat, color);
    }
}

// filter byte=1 means
// recon(x) = filt(x) + recon(a)
// a is the byte before,
// a is 0 for the first byte
fn filterLineSub(matrix: *Matrix(Color), line: []const u8, row: usize, fac: u8) Matrix(Color).MatrixError!void {
    const line_width: usize = matrix.w*fac;
    var idx_line: usize = 0;
    var idx_mat: usize = 0;

    var a: Color = Color.ZeroColor;
    
    while (idx_line < line_width) : ({
        idx_line += fac;
        idx_mat += 1;
    }) {
        
        const x: u8 = line[idx_line];
        var rgb: [3]u8 = [_]u8{x,x,x};
        
        for (1..fac) |l| {
            rgb[l] = line[idx_line+l];
        }

        const color = Color.add(
            Color{.r = rgb[0], .g = rgb[1], .b = rgb[2], .a = 255,},
            a
        );

        try matrix.set(row, idx_mat, color);
        a = color;
    }
}


fn filterLineUp(matrix: *Matrix(Color), line: []const u8, row: usize, fac: u8) Matrix(Color).MatrixError!void {
    const line_width: usize = matrix.w*fac;
    var idx_line: usize = 0;
    var idx_mat: usize = 0;
    
    while (idx_line < line_width) : ({
        idx_line += fac;
        idx_mat += 1;
    }) {
        const b: Color = if (row == 0) Color.ZeroColor else try matrix.get(row-1, idx_mat);
        const x: u8 = line[idx_line];
        var rgb: [3]u8 = [_]u8{x,x,x};
        
        for (1..fac) |l| {
            rgb[l] = line[idx_line+l];
        }

        const color = Color.add(
            Color{.r = rgb[0], .g = rgb[1], .b = rgb[2], .a = 255,},
            b
        );

        try matrix.set(row, idx_mat, color);
    }
}


fn filterLinePaethPredictor(matrix: *Matrix(Color), line: []const u8, row: usize, fac: u8) Matrix(Color).MatrixError!void {
    const line_width: usize = matrix.w*fac;
    var idx_line: usize = 0;
    var idx_mat: usize = 0;

    var a: Color = Color.ZeroColor;
    
    while (idx_line < line_width) : ({
        idx_line += fac;
        idx_mat += 1;
    }) {
        const b: Color = if (row == 0) Color.ZeroColor else try matrix.get(row-1, idx_mat);
        const c: Color = if ((row != 0) and (idx_mat != 0)) try matrix.get(row-1, idx_mat-1) else Color.ZeroColor;
        
        const x: u8 = line[idx_line];
        
        var rgb: [3]u8 = [_]u8{x,x,x};
        for (1..fac) |i| {
            rgb[i] = line[idx_line+i];
        }

        const color: Color = Color.add(
            Color{.r = rgb[0], .g = rgb[1], .b = rgb[2], .a = 255},
            PaethPredictor(a, b, c),
        );
       
        try matrix.set(row, idx_mat, color);
        a = color;
    }
    
}


fn PaethPredictor(a: Color, b: Color, c: Color) Color {
    var Pr: Color = Color.ZeroColor;
    const p:  Color = Color.add(a, Color.sub(b, c));
    const pa: Color = Color.sub(p, a);
    const pb: Color = Color.sub(p, b);
    const pc: Color = Color.sub(p, c);

    // lol
    // otherwise i guess I'd just make it a packed struct and just bit twiddle?
    const color_fields = comptime std.meta.fields(Color);
    inline for (color_fields) |field| {
        if ((@field(pa, field.name) <= @field(pb, field.name)) and (@field(pb, field.name) <= @field(pc, field.name))) {
            @field(Pr, field.name) = @field(a, field.name);
        } else if (@field(pb, field.name) <= @field(pc, field.name)) {
            @field(Pr, field.name) = @field(b, field.name);
        } else {
            @field(Pr, field.name) = @field(c, field.name);
        }
    }
    return Pr;
}


/// Returns a matrix consisting of RBG tuples
/// that can then be used directly into some graphical rending program.
/// NOTE: assumes a bit depth of 8!!!!
fn toMatrix(alloc: *const Allocator, idat_data: []const u8, color_type: u8, img_w: u32, img_h: u32) !Matrix(Color) {
    const buf: []Color = try alloc.alloc(Color, img_w*img_h);
    var matrix: Matrix(Color) = Matrix(Color).init(buf, img_w, img_h);

    // multiplicative factor
    // essentially just the number of bytes in a color
    const fac: u8 = switch(color_type) { 
        0 => 1, // grayscale
        2 => 3, // rgb/truecolor
        else => unreachable,
    };
    
    const line_width: usize = img_w*fac + 1; // +1 for filter byte

    
    for (0..img_h) |idx_h| {
        const row = idx_h*line_width;
        const filter_byte: u8 = idat_data[row];
        const line: []const u8 = idat_data[row+1..row + line_width]; // no filter byte
        switch (filter_byte) {
            0 => {try filterLineNone(&matrix, line, idx_h, fac);},
            1 => {try filterLineSub(&matrix, line, idx_h, fac);},
            2 => {try filterLineUp(&matrix, line, idx_h, fac);},
            3 => {@panic("Unsupported filter byte");},
            4 => {try filterLinePaethPredictor(&matrix, line, idx_h, fac);},
            else => {@panic("Unsupported filter byte");}
        }
    }

    return matrix;
}





// -------------
// Other type(s)
// -------------

pub const Chunk = struct{
    chunk_size: u32,
    chunk_name: [4]u8 = undefined,
    chunk_data: []const u8,
};



const Self = @This();
