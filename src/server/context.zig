const std = @import("std");
const pg = @import("pg");

pub const AppCtx = struct {
    pool: *pg.Pool,
    has_db: bool,
    jwt_secret: []const u8,
};
