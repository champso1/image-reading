const std = @import("std");
const Allocator = std.mem.Allocator;
const CRC32IEEE = std.hash.Crc32;


const png_signature = &[_]u8{ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };



// predefine CRC values on startup
const CRC32_POLYNOMIAL: u32 = 0xEDB88320;
var crc32_table: [256]u32 = undefined;
pub fn computeCRC32Table() void {
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
pub fn crc32(data: []const u8) u32 {
    var crc: u32 = 0xFFFFFFFF;

    for (data) |x| {
        crc = crc32_table[(crc ^ x) & 0xFF] ^ (crc >> 8);
    }

    return ~crc;
}





const Chunk = struct{
    name: []const u8,
    size: u32,
    data: []const u8,
    crc:  []const u8,


    // list of chunk names
    pub const ChunkNames = &[_][]const u8{
        &[_]u8{'I','H','D','R'},
        &[_]u8{'I','D','A','T'},
        &[_]u8{'t','E','X','t'},
        &[_]u8{'p','H','Y','s'},
        &[_]u8{'t','I','M','E'},
    };


    pub fn print(self: *const Chunk) void {
        std.debug.print("Name: {s}\n", .{self.name});
        std.debug.print("Size: {d}\n", .{self.size});
        std.debug.print("Data: {X:0>2}\n", .{self.data});
        std.debug.print("CRC: {X:0>2}\n", .{self.crc});
    }
};





// convertes an array of bytes to a 32-bit (unsigned) integer
// this is Big Endian, I believe, with the most significant byte first
pub fn byteArrToInt(byte_arr: []const u8) u32 {
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

pub fn intToByteArr(int: u32) [4]u8 {
    var arr = [_]u8{0, 0, 0, 0};

    arr[0] = @as(u8, @intCast((int >> 24) & 0xFF));
    arr[1] = @as(u8, @intCast((int >> 16) & 0xFF));
    arr[2] = @as(u8, @intCast((int >> 8) & 0xFF));
    arr[3] = @as(u8, @intCast(int & 0xFF));
    
    return arr;
}





const PNG = struct{
    data: []const u8,
    idx: usize, // current index of file path
    allocator: *const Allocator,


    // groups various errors together
    const PNGError = error{
        InvalidSignature,
        InvalidChunkName,
        InvalidCRC,
        EOF,
        InvalidChunk,
    };

    
    // checks the first 8 bytes to make sure its valid
    pub fn checkPNGSignature(signature: []const u8) bool {
        if (!std.mem.eql(u8, signature, png_signature)) {
            return false;
        }
        return true;
    }

    pub fn checkChunkName(chunk_name: []const u8) bool {
        for (Chunk.ChunkNames) |possible_chunk_name| {
            if (std.mem.eql(u8, possible_chunk_name, chunk_name)) return true;
        }
        return false;
    }

    
    pub fn checkCRC(self: *PNG, chunk: *const Chunk) bool {
        // we need an array of the concatenated bytes from the 
        // chunk's type and its data (but not the length)
        // as a []const u8

        const all_data = std.mem.concat(self.allocator.*, u8, &[_][]const u8{chunk.name, chunk.data}) catch |err| {
            std.debug.print("[ERROR] Could not concatenate chunk name and data.\n[INFO] Error description: {}\n", .{err});
            return false;
        };

        const crc: u32 = crc32(all_data);
        const crc_arr: [4]u8 = intToByteArr(crc);

        if (!std.mem.eql(u8, crc_arr[0..], chunk.crc)) {
            std.debug.print("[ERROR] CRC is invalid.\n", .{});
            return false;
        }

        return true;
    }
   



    



    // loads all of the bytes of the file into memory and checks if it is a valid png
    pub fn init(file_path: []const u8, allocator: *const Allocator, max_bytes: usize) !PNG {

        const file = try std.fs.cwd().openFile(file_path, .{});
        const data = try file.readToEndAlloc(allocator.*, max_bytes);

        if (!checkPNGSignature(data[0..8])) {
            return PNGError.InvalidSignature;
        }

        computeCRC32Table();
        
        return PNG{
            .data = data,
            .allocator = allocator,
            .idx = 8,
        };
    }

    // returns a slice to the next `num_bytes` in the loaded data
    pub fn advance(self: *PNG, num_bytes: usize) PNGError![]const u8 {
        // ensure we are not going past the end of the file
        if (num_bytes + self.idx >= self.data.len) {
            std.debug.print("ERROR: index {d}+{d} out of range for file size {d}\n", .{num_bytes, self.idx, self.data.len});
            return PNGError.EOF;
        }
        
        defer self.idx += num_bytes;
        return self.data[self.idx..(self.idx+num_bytes)];
    }
    

    // consolidates the next chunk into a Chunk structure and returns it
    // or an error of course
    pub fn getChunk(self: *PNG) PNGError!Chunk {

        const chunk_size_byte_arr = try self.advance(4);
        const chunk_size = byteArrToInt(chunk_size_byte_arr);
        
        const chunk_name = try self.advance(4);
        if (!checkChunkName(chunk_name)) {
            std.debug.print("ERROR: Invalid Chunk name: {s}\n", .{chunk_name});
            return PNGError.InvalidChunkName;
        }

        const data = try self.advance(chunk_size);

        const crc = try self.advance(4);

        const chunk = Chunk{
            .name = chunk_name,
            .size = chunk_size,
            .data = data,
            .crc = crc,
        };

        const isCRCValid: bool = self.checkCRC(&chunk);

        if (!isCRCValid) {
            std.debug.print("[ERROR]: CRC is invalid.\n", .{});
            return PNGError.InvalidCRC;
        }

        return chunk;
    }


    // returns text within the chunk
    // this one is easy, since the data is already a []const u8,
    // we can just return the data
    pub fn processTEXTChunk(chunk: Chunk) void {
        std.debug.print("----- tEXt Chunk -----\n", .{});
        std.debug.print("{s}\n", .{chunk.data});
    }


    pub fn processPHYSChunk(chunk: Chunk) void {
        std.debug.print("----- pHYs Chunk -----\n", .{});
        std.debug.print("Pixels per Unit (X): {d}\nPixels Per Unit (Y): {d}\n", .{
            byteArrToInt(chunk.data[0..4]), byteArrToInt(chunk.data[4..8]),
        });
        
        if (chunk.data[8] == 1) {
            std.debug.print("Units: Meters\n", .{});
        }
    }



    pub fn processTIMEChunk(chunk: Chunk) void {
        std.debug.print("----- TIME Chunk -----\n", .{});
        const year: u16 = (chunk.data[0] << 1) | (chunk.data[1]);
        std.debug.print("Date created: {d}/{d}/{d} {d}:{d}:{s}\n", .{
            year, chunk.data[2], chunk.data[3],
            chunk.data[4], chunk.data[5], chunk.data[6],
        });
    }


    

};


pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var file = try PNG.init("./res/pic.png", &allocator, 8*1000);
    
    const chunk1 = try file.getChunk();
    chunk1.print();
    const chunk2 = try file.getChunk();
    PNG.processPHYSChunk(chunk2);
    const chunk3 = try file.getChunk();
    chunk3.print();
}
