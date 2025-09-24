const std = @import("std");     
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const utils = @import("utils.zig");
const Matrix = utils.Matrix;

const rl = @import("raylib");


// this is what should be the first eight bytes of the file
pub const PNG_SIGNATURE: [8]u8 = [_]u8{
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A
};


// in case the allocator's state gets changed, we store a pointer to the main one
alloc: *const Allocator,


// this is the important information from the header
// other things are either largely irrelevant or always 0
img_w: u32,
img_h: u32,
bit_depth: u8,
color_type: u8,

// this is the uncompressed/inflated/raw image data
// reconstructed from the scanlines scanlines
// represented as a simple 2d matrix of colors
img_data: Matrix(rl.Color),

// we may not care about any auxilliary chunks so this is optional
// NOTE: we do not care about this at all at the moment!
aux_chunks: ?[]Chunk = null,


// errors that can be raised in reading the PNG file
pub const PNGError = error{
    InvalidFile,
    InvalidSignature,
    InvalidHeader,
    InvalidChunkCRC,
};


// takes a pointer to some allocator and a png file handle
// will parse the entire file, storing the main header fields
// and generic auxilliary chunks in an array
// will reconstruct the raw colors values of the image into a matrix
// returns a `PNGFile` to the caller.
pub fn init(alloc: *const Allocator, file_handle: std.fs.File) !Self {
    // new interface for Readers/Writers use a user-defined buffer
    // for effiency. this buffer is not the contents
    // of the underlying stream that is being read (I think)
    var reader_buf: [4096]u8 = undefined;

    var file_reader = file_handle.reader(&reader_buf);
    var reader = &file_reader.interface;

    const signature_bytes = try reader.takeArray(8);
    if (!std.mem.eql(u8, signature_bytes, PNG_SIGNATURE[0..])) {
        std.debug.print("[ERROR] Invalid PNG signature. Found {X} but expected {X:0>2}\n", .{
            signature_bytes[0..], PNG_SIGNATURE[0..],
        });
        return PNGError.InvalidSignature;
    } else {
        std.debug.print("[INFO] Valid PNG signature found: {X}.\n", .{signature_bytes[0..]});
    }

    const ihdr_bytes = try reader.takeArray(25);

    // header contains:
    //   size: 4 bytes
    //   name: 4 bytes (should be 'IHDR')
    //   data: 13 bytes
    //   CRC:  4 bytes
    
    const ihdr_size: u32 = utils.byteArrToInt(ihdr_bytes[0..4]);    
    if (ihdr_size != 13) {
        std.debug.print("[ERROR] Invalid header size. Expected 13 but found {d}\n", .{ihdr_size});
        return PNGError.InvalidHeader;
    } else {
        std.debug.print("[INFO] Valid header size of 13 bytes found.\n", .{});
    }
    
    const ihdr_name = ihdr_bytes[4..8];
    if (!std.mem.eql(u8, ihdr_name, "IHDR")) {
        std.debug.print("[ERROR] Invalid header name. Expected \"IHDR\" but found {s}\n", .{ihdr_name});
        return PNGError.InvalidHeader;
    } else {
        std.debug.print("[INFO] Found valid header chunk with header name \"IHDR\".\n", .{});
    }
    
    // at this point we assume everything is okay and just read the rest in
    const ihdr_data: []const u8 = ihdr_bytes[8..21];
    const img_w: u32 = utils.byteArrToInt(ihdr_data[0..4]);
    const img_h: u32 = utils.byteArrToInt(ihdr_data[4..8]);
    const bit_depth: u8 = ihdr_data[8];
    const color_type: u8 = ihdr_data[9];
    // again, the rest of the bytes we don't care about (yet)

    std.debug.print("[INFO] The image has a size of {d}x{d}.\n", .{img_w, img_h});
    std.debug.print("[INFO] The image has a bit depth of {d}.\n", .{bit_depth});
    std.debug.print("[INFO] The image has a color type of {d}.\n", .{color_type});

    
    const ihdr_crc: u32 = utils.byteArrToInt(ihdr_bytes[21..25]);
    const ihdr_crc_calculated: u32 = utils.crc32(ihdr_bytes[4..21]);
    if (ihdr_crc != ihdr_crc_calculated) {
        std.debug.print("[ERROR] Header CRC invalid. Expected 0x{X} but found 0x{X}.\n", .{ihdr_crc_calculated, ihdr_crc});
        return PNGError.InvalidHeader;
    } else {
        std.debug.print("[INFO] Calculated CRC and provided CRC match: 0x{X}.\n", .{ihdr_crc_calculated});
    }

    // with this, the header has been parsed. all we care about now is the IDAT chunk
    // we loop over all the chunks, storing ancillary/auxilliary chunks in their entirety
    // and parsing the IDAT chunk once we find it
    
    var img_data: Matrix(rl.Color) = undefined;

    // first grab the name (before which we need the size)
    // then we can just loop until that name is 'IEND'
    
    
    var chunk_size_arr = try reader.takeArray(4);
    var chunk_size = utils.byteArrToInt(chunk_size_arr);
    // i choose to read in the entirety of the rest of the chunk including the name, data, and crc
    var chunk_array_size = chunk_size + 4 + 4;
    var chunk_data = try reader.take(@intCast(chunk_array_size));
    var chunk_name = chunk_data[0..4];
    
    while (!std.mem.eql(u8, chunk_name, "IEND")) {
        std.debug.print("[INFO] Found {s} chunk with size {d}.\n", .{chunk_name, chunk_size});
        if (chunk_size <= 64) {
            std.debug.print("[INFO] Chunk is small enough to print. The contents are:\n{x}\n", .{chunk_data[4..chunk_size+4]});
        }

        const chunk_crc_arr = chunk_data[chunk_array_size-4..chunk_array_size];
        const chunk_crc: u32 = utils.byteArrToInt(chunk_crc_arr[0..4]);
        const crc_calculated: u32 = utils.crc32(chunk_data[0..chunk_array_size-4]);

        if (chunk_crc != crc_calculated) {
            std.debug.print("[ERROR] {s} chunk CRC is invalid.\n[INFO] Expected: 0x{X}, but got 0x{X}\n", .{chunk_name, crc_calculated, chunk_crc});
            return PNGError.InvalidChunkCRC;
        } else {
            std.debug.print("[INFO] {s} chunk calculated CRC matches the provided: 0x{X}.\n", .{chunk_name, crc_calculated});
        }
        
        if (std.mem.eql(u8, chunk_name, "IDAT")) {
            // must decompress
            const bytes = chunk_data[4..chunk_size+4];
            var bytes_reader = std.Io.Reader.fixed(bytes);
            std.debug.print("[INFO] Raw, deflated bytes:\n{any}\n", .{bytes});
            
            var inflated_bytes: [1028]u8 = [_]u8{0} ** 1028;
            var bytes_writer = std.io.Writer.fixed(&inflated_bytes);
            
            var decompressor = std.compress.flate.Decompress.init(&bytes_reader, .zlib, &.{});
            const decompressor_reader = &decompressor.reader;
            
            const num_bytes = try decompressor_reader.streamRemaining(&bytes_writer);
            std.debug.print("[INFO] Allegedly, we have a buffer of sheisse now:\n{x}\n", .{inflated_bytes[0..num_bytes]});

            img_data = try toMatrix(alloc, &inflated_bytes, color_type, img_w, img_h);
            
            break;
        } else {
            std.debug.print("[INFO] Found {s} chunk. Skipping...\n", .{chunk_name});
        }

        // recalculate the new stuff
        chunk_size_arr = try reader.takeArray(4);
        chunk_size = utils.byteArrToInt(chunk_size_arr[0..4]);
        chunk_array_size = chunk_size + 4 + 4;
        chunk_data = try reader.take(@intCast(chunk_array_size));
        chunk_name = chunk_data[0..4];
    }

    return .{
        .alloc = alloc,
        
        .img_w = img_w,
        .img_h = img_h,
        .bit_depth = bit_depth,
        .color_type = color_type,
        
        .img_data = img_data,
    };
}



/// filter byte=0 means that there is no filtering,
/// i.e. recon(x) = filt(x)
fn filterLineNone(matrix: *Matrix(rl.Color), line: []const u8, row: usize, fac: u8) !void {
    // std.debug.print("{d} ", .{row});
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

        const color = rl.Color.init(rgb[0], rgb[1], rgb[2], 255);

        try matrix.set(row, idx_mat, color);
    }
}

// filter byte=1 means
// recon(x) = filt(x) + recon(a)
// a is the byte before,
// a is 0 for the first byte
fn filterLineSub(matrix: *Matrix(rl.Color), line: []const u8, row: usize, fac: u8) !void {
    const line_width: usize = matrix.w*fac;
    var idx_line: usize = 0;
    var idx_mat: usize = 0;

    var a = rl.Color.blank;
    
    while (idx_line < line_width) : ({
        idx_line += fac;
        idx_mat += 1;
    }) {
        
        const x: u8 = line[idx_line];
        var rgb: [3]u8 = [_]u8{x,x,x};
        
        for (1..fac) |l| {
            rgb[l] = line[idx_line+l];
        }

        const color = rl.Color.init(
            rgb[0] +% a.r,
            rgb[1] +% a.g,
            rgb[2] +% a.b,
            255
        );

        try matrix.set(row, idx_mat, color);
        a = color;
    }
}


fn filterLineUp(matrix: *Matrix(rl.Color), line: []const u8, row: usize, fac: u8) !void {
    const line_width: usize = matrix.w*fac;
    var idx_line: usize = 0;
    var idx_mat: usize = 0;
    
    while (idx_line < line_width) : ({
        idx_line += fac;
        idx_mat += 1;
    }) {
        const b: rl.Color = if (row == 0) rl.Color.blank else try matrix.get(row-1, idx_mat);
        const x: u8 = line[idx_line];
        var rgb: [3]u8 = [_]u8{x,x,x};
        
        for (1..fac) |l| {
            rgb[l] = line[idx_line+l];
        }

        const color = rl.Color.init(
            rgb[0] +% b.r,
            rgb[1] +% b.g,
            rgb[2] +% b.b,
            255
        );

        try matrix.set(row, idx_mat, color);
    }
}


fn filterLinePaethPredictor(matrix: *Matrix(rl.Color), line: []const u8, row: usize, fac: u8) !void {
    const line_width: usize = matrix.w*fac;
    var idx_line: usize = 0;
    var idx_mat: usize = 0;

    var a = rl.Color.black;
    
    while (idx_line < line_width) : ({
        idx_line += fac;
        idx_mat += 1;
    }) {
        const b: rl.Color = if (row == 0) rl.Color.black else try matrix.get(row-1, idx_mat);
        const c: rl.Color = if ((row != 0) and (idx_mat != 0)) try matrix.get(row-1, idx_mat-1) else rl.Color.black;
        
        const x: u8 = line[idx_line];
        
        var rgb: [3]u8 = [_]u8{x,x,x};
        for (1..fac) |i| {
            rgb[i] = line[idx_line+i];
        }

        const p = PaethPredictor(a, b, c);
        const color = rl.Color.init(
            rgb[0] +% p.r,
            rgb[1] +% p.g,
            rgb[2] +% p.b,
            255
        );
       
        try matrix.set(row, idx_mat, color);
        a = color;
    }
    
}


fn PaethPredictor(a: rl.Color, b: rl.Color, c: rl.Color) rl.Color {
    var Pr: rl.Color = rl.Color.black;

    const temp = rl.Color.init(
        b.r -% c.r,
        b.g -% c.g,
        b.b -% c.b,
        255
    );
    const p = rl.Color.init(
        a.r +% temp.r,
        a.g +% temp.g,
        a.b +% temp.b,
        255
    );
    const pa = rl.Color.init(
        p.r -% a.r,
        p.g -% a.g,
        p.b -% a.b,
        255
    );
    const pb = rl.Color.init(
        p.r -% b.r,
        p.g -% b.g,
        p.b -% b.b,
        255
    );
    const pc = rl.Color.init(
        p.r -% c.r,
        p.g -% c.g,
        p.b -% c.b,
        255
    );

    // this looks awful
    const color_fields = comptime std.meta.fields(rl.Color);
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
fn toMatrix(alloc: *const Allocator, idat_data: []const u8, color_type: u8, img_w: u32, img_h: u32) !Matrix(rl.Color) {
    const buf: []rl.Color = try alloc.alloc(rl.Color, img_w*img_h);
    var matrix = Matrix(rl.Color).init(buf, img_w, img_h);

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
            3 => {@panic("Unsupported filter byte 3");},
            4 => {try filterLinePaethPredictor(&matrix, line, idx_h, fac);},
            else => {@panic("Unsupported filter byte (!= 0,1,2,4)");}
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
