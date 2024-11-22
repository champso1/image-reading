const std = @import("std");
const Allocator = std.mem.Allocator;


const png_signature = &[_]u8{ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };




const Chunk = struct{
    name: [] const u8,
    size: u32,
    data: []const u8,
    crc: []const u8,


    // list of chunk names
    pub const ChunkNames = &[_][]const u8{
        &[_]u8{'I','H','D','R'},
        &[_]u8{'I','D','A','T'},
        &[_]u8{'t','E','X','t'},
        &[_]u8{'p','H','Y','s'},
    };


    pub fn print(self: *const Chunk) void {
        std.debug.print("Name: {s}\n", .{self.name});
        std.debug.print("Size: {d}\n", .{self.size});
        
        std.debug.print("Data: [", .{});
        for (self.data) |x| {
            std.debug.print("{X:0>2} ", .{x});
        }
        std.debug.print("]\n", .{});
        
        std.debug.print("CRC: [", .{});
        for (self.crc) |x| {
            std.debug.print("{X:0>2} ", .{x});
        }
        std.debug.print("]\n", .{});
    }
};




const PNG = struct{
    data: []const u8,
    idx: usize, // current index of file path
    allocator: *const Allocator,


    // groups various errors together
    const PNGError = error{
        InvalidSignature,
        InvalidChunkName,
        InvalidCRC,
        EOF
    };

    
    // groups all of the validation/checking functions together
    const PNGChecking = struct{
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

        pub fn checkCRC(crc: []const u8) bool {
            _ = crc;
            std.debug.print("---------------\nTODO: implement CRC checking.\n---------------\n", .{});
            return true;
        }
    };


    



    // loads all of the bytes of the file into memory and checks if it is a valid png
    pub fn init(file_path: []const u8, allocator: *const Allocator, max_bytes: usize) !PNG {

        const file = try std.fs.cwd().openFile(file_path, .{});
        const data = try file.readToEndAlloc(allocator.*, max_bytes);

        if (!PNGChecking.checkPNGSignature(data[0..8])) {
            return PNGError.InvalidSignature;
        }
        
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
    

    // convertes an array of bytes to a 32-bit (unsigned) integer
    // TODO: is this little or big endian? no one knows, but it works!
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
    

    // consolidates the next chunk into a Chunk structure and returns it
    // or an error of course
    pub fn getChunk(self: *PNG) PNGError!Chunk {

        const chunk_size_byte_arr = try self.advance(4);
        const chunk_size = byteArrToInt(chunk_size_byte_arr);
        
        const chunk_name = try self.advance(4);
        if (!PNGChecking.checkChunkName(chunk_name)) {
            std.debug.print("ERROR: Invalid Chunk name: {X:0>2}\n", .{chunk_name});
            return PNGError.InvalidChunkName;
        }

        const data = try self.advance(chunk_size);

        const crc = try self.advance(4);
        if (!PNGChecking.checkCRC(crc)) {
            return PNGError.InvalidCRC;
        }

        return Chunk{
            .name = chunk_name,
            .size = chunk_size,
            .data = data,
            .crc = crc
        };
        
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
    chunk2.print();

    

    

    
    _ = &file;
}
