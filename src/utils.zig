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

