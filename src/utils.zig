const std = @import("std");

// convertes an array of bytes to a 32-bit (unsigned) integer
// this is Big Endian, I believe, with the most significant byte first
pub fn byteArrToInt(byte_arr: [4]u8) u32 {
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
pub fn intToByteArr(int: u32) [4]u8 {
    var arr = [_]u8{0, 0, 0, 0};

    arr[0] = @as(u8, @intCast((int >> 24) & 0xFF));
    arr[1] = @as(u8, @intCast((int >> 16) & 0xFF));
    arr[2] = @as(u8, @intCast((int >> 8) & 0xFF));
    arr[3] = @as(u8, @intCast(int & 0xFF));
    
    return arr;
}





// predefine CRC values/table on startup
const CRC32_POLYNOMIAL: u32 = 0xEDB88320;
var crc32_table: [256]u32 = undefined;
var crc32_table_filled: bool = false;
pub fn computeCRC32Table() void {
    if (crc32_table_filled) return;
    
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
    crc32_table_filled = true;
}

pub fn crc32(data: []const u8) u32 {
    computeCRC32Table();
    
    var crc: u32 = 0xFFFFFFFF;

    for (data) |x| {
        crc = crc32_table[(crc ^ x) & 0xFF] ^ (crc >> 8);
    }

    return ~crc;
}



pub fn Matrix(T: anytype) type {
    return struct{
        const Self = @This();
        
        w: usize,
        h: usize,

        data: []T,

        pub fn init(data: []T, width: usize, height: usize) Self {
            return .{
                .data = data,
                .w = width,
                .h = height,
            };
        }

        pub const MatrixError = error{
            IndexOutOfBounds,
        };
        
        pub fn get(self: *Self, row: usize, col: usize) MatrixError!T {
            if (row >= self.h or col >= self.w) return MatrixError.IndexOutOfBounds;

            return self.data[row*self.w + col];
        }

        pub fn set(self: *Self, row: usize, col: usize, val: T) MatrixError!void {
            if (row >= self.h or col >= self.w) return MatrixError.IndexOutOfBounds;

            self.data[row*self.w + col] = val;
        }
    };
}


const rl = @import("raylib.zig");



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

    pub const ZeroColor = Color{
        .r = 0, .g = 0, .b = 0, .a = 255,
    };

    pub fn add(color1: Color, color2: Color) Color {
        return Color{
            .r = color1.r +% color2.r,
            .g = color1.g +% color2.g,
            .b = color1.b +% color2.b,
            .a = 255,
        };
    }

    pub fn sub(color1: Color, color2: Color) Color {
        return Color{
            .r = color1.r -% color2.r,
            .g = color1.g -% color2.g,
            .b = color1.b -% color2.b,
            .a = 255,
        };
    }
};
