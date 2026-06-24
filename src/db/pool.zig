const std = @import("std");
const pg = @import("pg");

pub const Pool = pg.Pool;

pub fn init(allocator: std.mem.Allocator, database_url: []const u8) !*Pool {
    return Pool.init(allocator, .{
        .connect = .{
            .connection_string = database_url,
        },
        .size = 5,
    });
}

test "pool module compiles" {
    // Verify types are accessible without a live DB.
    const T = Pool;
    _ = T;
}
