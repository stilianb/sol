const std = @import("std");
const pg = @import("pg");

pub const AppCtx = struct {
    pool: *pg.Pool,
    jwt_secret: []const u8,
};
