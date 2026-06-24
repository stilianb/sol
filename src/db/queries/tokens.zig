const std = @import("std");
const pg = @import("pg");

pub const RefreshTokenRow = struct {
    id: []const u8,
    user_id: []const u8,
    token_hash: []const u8,
    expires_at: i64,
    revoked_at: ?i64,
    allocator: std.mem.Allocator,

    pub fn deinit(self: RefreshTokenRow) void {
        self.allocator.free(self.id);
        self.allocator.free(self.user_id);
        self.allocator.free(self.token_hash);
    }
};

pub fn createRefreshToken(
    pool: *pg.Pool,
    user_id: []const u8,
    token_hash: []const u8,
    expires_at: i64,
    allocator: std.mem.Allocator,
) !void {
    _ = pool;
    _ = user_id;
    _ = token_hash;
    _ = expires_at;
    _ = allocator;
    return error.NotImplemented;
}

pub fn findRefreshToken(
    pool: *pg.Pool,
    token_hash: []const u8,
    allocator: std.mem.Allocator,
) !?RefreshTokenRow {
    _ = pool;
    _ = token_hash;
    _ = allocator;
    return error.NotImplemented;
}

pub fn revokeRefreshToken(pool: *pg.Pool, token_hash: []const u8) !void {
    _ = pool;
    _ = token_hash;
    return error.NotImplemented;
}

pub fn revokeAllUserTokens(pool: *pg.Pool, user_id: []const u8) !void {
    _ = pool;
    _ = user_id;
    return error.NotImplemented;
}

test "RefreshTokenRow deinit without revoked_at" {
    const allocator = std.testing.allocator;
    const row = RefreshTokenRow{
        .id = try allocator.dupe(u8, "tok-uuid"),
        .user_id = try allocator.dupe(u8, "user-uuid"),
        .token_hash = try allocator.dupe(u8, "sha256hash"),
        .expires_at = 9999999999,
        .revoked_at = null,
        .allocator = allocator,
    };
    row.deinit();
}
