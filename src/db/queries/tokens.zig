const std = @import("std");
const pg = @import("pg");

fn nowMicroSec() i64 {
    var ts: std.c.timespec = .{ .sec = 0, .nsec = 0 };
    _ = std.c.clock_gettime(std.c.CLOCK.REALTIME, &ts);
    return @as(i64, ts.sec) * 1_000_000 + @divTrunc(@as(i64, ts.nsec), 1000);
}

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

    pub fn isValid(self: RefreshTokenRow) bool {
        const now_us = nowMicroSec();
        return self.revoked_at == null and self.expires_at > now_us;
    }
};

fn rowToToken(row: anytype, allocator: std.mem.Allocator) !RefreshTokenRow {
    const id_bytes = try row.get([]const u8, 0);
    const id_str = try pg.types.UUID.toString(id_bytes);
    const user_id_bytes = try row.get([]const u8, 1);
    const user_id_str = try pg.types.UUID.toString(user_id_bytes);
    const token_hash = try row.get([]const u8, 2);
    const expires_at = try row.get(i64, 3);
    const revoked_at = try row.get(?i64, 4);
    return RefreshTokenRow{
        .id = try allocator.dupe(u8, &id_str),
        .user_id = try allocator.dupe(u8, &user_id_str),
        .token_hash = try allocator.dupe(u8, token_hash),
        .expires_at = expires_at,
        .revoked_at = revoked_at,
        .allocator = allocator,
    };
}

pub fn create(
    pool: *pg.Pool,
    user_id: []const u8,
    token_hash: []const u8,
    expires_at_us: i64,
    allocator: std.mem.Allocator,
) !void {
    _ = allocator;
    var conn = try pool.acquire();
    defer conn.release();
    _ = try conn.exec(
        "INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1::uuid, $2, to_timestamp($3))",
        .{ user_id, token_hash, @as(f64, @floatFromInt(expires_at_us)) / 1_000_000.0 },
    );
}

pub fn findByHash(
    pool: *pg.Pool,
    token_hash: []const u8,
    allocator: std.mem.Allocator,
) !?RefreshTokenRow {
    var conn = try pool.acquire();
    defer conn.release();

    var row_opt = try conn.row(
        "SELECT id, user_id, token_hash, EXTRACT(EPOCH FROM expires_at)::bigint * 1000000, EXTRACT(EPOCH FROM revoked_at)::bigint * 1000000 FROM refresh_tokens WHERE token_hash = $1",
        .{token_hash},
    );
    if (row_opt) |*row| {
        defer row.deinit() catch {};
        return try rowToToken(row, allocator);
    }
    return null;
}

pub fn revoke(pool: *pg.Pool, token_hash: []const u8) !void {
    var conn = try pool.acquire();
    defer conn.release();
    _ = try conn.exec(
        "UPDATE refresh_tokens SET revoked_at = NOW() WHERE token_hash = $1",
        .{token_hash},
    );
}

pub fn revokeAllForUser(pool: *pg.Pool, user_id: []const u8) !void {
    var conn = try pool.acquire();
    defer conn.release();
    _ = try conn.exec(
        "UPDATE refresh_tokens SET revoked_at = NOW() WHERE user_id = $1 AND revoked_at IS NULL",
        .{user_id},
    );
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

test "RefreshTokenRow isValid: not revoked and not expired" {
    const row = RefreshTokenRow{
        .id = "",
        .user_id = "",
        .token_hash = "",
        .expires_at = nowMicroSec() + 1_000_000_000,
        .revoked_at = null,
        .allocator = std.testing.allocator,
    };
    try std.testing.expect(row.isValid());
}

test "RefreshTokenRow isValid: expired returns false" {
    const row = RefreshTokenRow{
        .id = "",
        .user_id = "",
        .token_hash = "",
        .expires_at = nowMicroSec() - 1_000_000,
        .revoked_at = null,
        .allocator = std.testing.allocator,
    };
    try std.testing.expect(!row.isValid());
}
