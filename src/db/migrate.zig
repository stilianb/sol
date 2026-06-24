const std = @import("std");
const pg = @import("pg");

pub const Migration = struct {
    version: []const u8,
    sql: []const u8,
};

/// Run pending migrations against the pool.
/// Creates schema_migrations if absent, then applies each migration
/// whose version is not yet recorded.
/// requires live DB — not called from unit tests
pub fn run(pool: *pg.Pool, migrations: []const Migration, allocator: std.mem.Allocator) !void {
    _ = allocator;
    var conn = try pool.acquire();
    defer conn.release();

    _ = try conn.exec(
        \\CREATE TABLE IF NOT EXISTS schema_migrations (
        \\    version TEXT PRIMARY KEY,
        \\    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        \\)
    , .{});

    for (migrations) |m| {
        var exists = try conn.row(
            "SELECT 1 FROM schema_migrations WHERE version = $1",
            .{m.version},
        );
        if (exists) |*r| {
            r.deinit() catch {};
            continue;
        }

        _ = try conn.exec(m.sql, .{});
        _ = try conn.exec(
            "INSERT INTO schema_migrations (version) VALUES ($1)",
            .{m.version},
        );
    }
}

// --- version sorting / dedup logic (no DB required) ---

/// Returns true if versions slice contains no duplicates.
pub fn noDuplicates(migrations: []const Migration) bool {
    for (migrations, 0..) |a, i| {
        for (migrations[i + 1 ..]) |b| {
            if (std.mem.eql(u8, a.version, b.version)) return false;
        }
    }
    return true;
}

/// Returns true if versions are in lexicographic ascending order.
pub fn isSorted(migrations: []const Migration) bool {
    for (migrations, 0..) |m, i| {
        if (i == 0) continue;
        if (std.mem.order(u8, migrations[i - 1].version, m.version) != .lt) return false;
    }
    return true;
}

test "noDuplicates: unique versions" {
    const ms = [_]Migration{
        .{ .version = "001", .sql = "" },
        .{ .version = "002", .sql = "" },
        .{ .version = "003", .sql = "" },
    };
    try std.testing.expect(noDuplicates(&ms));
}

test "noDuplicates: detects duplicate" {
    const ms = [_]Migration{
        .{ .version = "001", .sql = "" },
        .{ .version = "001", .sql = "" },
    };
    try std.testing.expect(!noDuplicates(&ms));
}

test "isSorted: ascending order" {
    const ms = [_]Migration{
        .{ .version = "001", .sql = "" },
        .{ .version = "002", .sql = "" },
        .{ .version = "003", .sql = "" },
    };
    try std.testing.expect(isSorted(&ms));
}

test "isSorted: out of order" {
    const ms = [_]Migration{
        .{ .version = "002", .sql = "" },
        .{ .version = "001", .sql = "" },
    };
    try std.testing.expect(!isSorted(&ms));
}

test "isSorted: single entry" {
    const ms = [_]Migration{
        .{ .version = "001", .sql = "" },
    };
    try std.testing.expect(isSorted(&ms));
}
