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

pub fn create(
    pool: *pg.Pool,
    email: []const u8,
    password_hash: ?[]const u8,
    allocator: std.mem.Allocator,
) !UserRow {
    _ = pool;
    _ = email;
    _ = password_hash;
    _ = allocator;
    return error.NotImplemented;
}

pub fn findByEmail(
    pool: *pg.Pool,
    email: []const u8,
    allocator: std.mem.Allocator,
) !?UserRow {
    _ = pool;
    _ = email;
    _ = allocator;
    return error.NotImplemented;
}

pub fn findById(
    pool: *pg.Pool,
    id: []const u8,
    allocator: std.mem.Allocator,
) !?UserRow {
    _ = pool;
    _ = id;
    _ = allocator;
    return error.NotImplemented;
}

pub fn setEmailVerified(pool: *pg.Pool, user_id: []const u8) !void {
    _ = pool;
    _ = user_id;
    return error.NotImplemented;
}

pub fn updatePasswordHash(
    pool: *pg.Pool,
    user_id: []const u8,
    hash: []const u8,
) !void {
    _ = pool;
    _ = user_id;
    _ = hash;
    return error.NotImplemented;
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
