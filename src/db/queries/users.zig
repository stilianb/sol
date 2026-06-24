const std = @import("std");
const pg = @import("pg");

pub const UserRow = struct {
    id: []const u8,
    email: []const u8,
    password_hash: ?[]const u8,
    email_verified: bool,
    mfa_enabled: bool,
    allocator: std.mem.Allocator,

    pub fn deinit(self: UserRow) void {
        self.allocator.free(self.id);
        self.allocator.free(self.email);
        if (self.password_hash) |h| self.allocator.free(h);
    }
};

fn rowToUser(row: anytype, allocator: std.mem.Allocator) !UserRow {
    const id_bytes = try row.get([]const u8, 0);
    const id_str = try pg.types.UUID.toString(id_bytes);
    const email = try row.get([]const u8, 1);
    const pw_hash = try row.get(?[]const u8, 2);
    const email_verified = try row.get(bool, 3);
    const mfa_enabled = try row.get(bool, 4);
    return UserRow{
        .id = try allocator.dupe(u8, &id_str),
        .email = try allocator.dupe(u8, email),
        .password_hash = if (pw_hash) |h| try allocator.dupe(u8, h) else null,
        .email_verified = email_verified,
        .mfa_enabled = mfa_enabled,
        .allocator = allocator,
    };
}

pub fn create(
    pool: *pg.Pool,
    email: []const u8,
    password_hash: ?[]const u8,
    allocator: std.mem.Allocator,
) !UserRow {
    var conn = try pool.acquire();
    defer conn.release();

    var row_opt = try conn.row(
        "INSERT INTO users (email, password_hash) VALUES ($1, $2) RETURNING id, email, password_hash, email_verified, mfa_enabled",
        .{ email, password_hash },
    );
    if (row_opt) |*row| {
        defer row.deinit() catch {};
        return rowToUser(row, allocator);
    }
    return error.InsertFailed;
}

pub fn findByEmail(
    pool: *pg.Pool,
    email: []const u8,
    allocator: std.mem.Allocator,
) !?UserRow {
    var conn = try pool.acquire();
    defer conn.release();

    var row_opt = try conn.row(
        "SELECT id, email, password_hash, email_verified, mfa_enabled FROM users WHERE email = $1",
        .{email},
    );
    if (row_opt) |*row| {
        defer row.deinit() catch {};
        return try rowToUser(row, allocator);
    }
    return null;
}

pub fn findById(
    pool: *pg.Pool,
    id: []const u8,
    allocator: std.mem.Allocator,
) !?UserRow {
    var conn = try pool.acquire();
    defer conn.release();

    var row_opt = try conn.row(
        "SELECT id, email, password_hash, email_verified, mfa_enabled FROM users WHERE id = $1",
        .{id},
    );
    if (row_opt) |*row| {
        defer row.deinit() catch {};
        return try rowToUser(row, allocator);
    }
    return null;
}

pub fn setEmailVerified(pool: *pg.Pool, user_id: []const u8) !void {
    var conn = try pool.acquire();
    defer conn.release();
    _ = try conn.exec("UPDATE users SET email_verified = TRUE WHERE id = $1", .{user_id});
}

pub fn updatePasswordHash(pool: *pg.Pool, user_id: []const u8, new_hash: []const u8) !void {
    var conn = try pool.acquire();
    defer conn.release();
    _ = try conn.exec("UPDATE users SET password_hash = $1 WHERE id = $2", .{ new_hash, user_id });
}

test "UserRow deinit with null password_hash" {
    const allocator = std.testing.allocator;
    const row = UserRow{
        .id = try allocator.dupe(u8, "uuid-1"),
        .email = try allocator.dupe(u8, "a@b.com"),
        .password_hash = null,
        .email_verified = false,
        .mfa_enabled = false,
        .allocator = allocator,
    };
    row.deinit();
}

test "UserRow deinit with password_hash" {
    const allocator = std.testing.allocator;
    const row = UserRow{
        .id = try allocator.dupe(u8, "uuid-2"),
        .email = try allocator.dupe(u8, "c@d.com"),
        .password_hash = try allocator.dupe(u8, "hash"),
        .email_verified = true,
        .mfa_enabled = false,
        .allocator = allocator,
    };
    row.deinit();
}
