const std = @import("std");
const Io = std.Io;
const pg = @import("pg");

pub const Pool = pg.Pool;

pub fn initFromUrl(io: Io, allocator: std.mem.Allocator, database_url: []const u8) !*Pool {
    const uri = try std.Uri.parse(database_url);
    return Pool.initUri(io, allocator, uri, .{ .size = 5 });
}

test "pool module exports Pool type" {
    try std.testing.expect(Pool == pg.Pool);
}
