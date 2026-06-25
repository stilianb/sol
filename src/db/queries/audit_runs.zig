const std = @import("std");
const pg = @import("pg");

pub const AuditRunSummary = struct {
    id: []const u8,
    url: []const u8,
    profile: []const u8,
    ran_at_us: i64,
    scores_json: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: AuditRunSummary) void {
        self.allocator.free(self.id);
        self.allocator.free(self.url);
        self.allocator.free(self.profile);
        self.allocator.free(self.scores_json);
    }
};

/// Store an audit run. Returns heap-allocated run id (UUID text). Caller frees.
pub fn store(
    pool: *pg.Pool,
    user_id_opt: ?[]const u8,
    url: []const u8,
    profile_name: []const u8,
    scores_json: []const u8,
    psi_json_opt: ?[]const u8,
    builtwith_json_opt: ?[]const u8,
    allocator: std.mem.Allocator,
) ![]const u8 {
    var conn = try pool.acquire();
    defer conn.release();

    var row_opt = try conn.row(
        "INSERT INTO audit_runs (user_id, url, profile, scores, psi, builtwith) VALUES ($1::uuid, $2, $3, $4::jsonb, $5::jsonb, $6::jsonb) RETURNING id",
        .{ user_id_opt, url, profile_name, scores_json, psi_json_opt, builtwith_json_opt },
    );
    if (row_opt) |*row| {
        defer row.deinit() catch {};
        const id_bytes = try row.get([]const u8, 0);
        const id_str = try pg.types.UUID.toString(id_bytes);
        return allocator.dupe(u8, &id_str);
    }
    return error.InsertFailed;
}

/// List recent audit runs for a URL (latest 20). Caller frees:
///   for (rows) |r| r.deinit(); allocator.free(rows);
pub fn listByUrl(
    pool: *pg.Pool,
    url: []const u8,
    allocator: std.mem.Allocator,
) ![]AuditRunSummary {
    var conn = try pool.acquire();
    defer conn.release();

    var result = try conn.query(
        "SELECT id, url, profile, EXTRACT(EPOCH FROM ran_at)::bigint * 1000000, COALESCE(scores::text, 'null') FROM audit_runs WHERE url = $1 ORDER BY ran_at DESC LIMIT 20",
        .{url},
    );
    defer result.deinit();

    var list: std.ArrayList(AuditRunSummary) = .empty;
    errdefer {
        for (list.items) |r| r.deinit();
        allocator.free(list.items);
    }

    while (try result.next()) |row| {
        const id_bytes = try row.get([]const u8, 0);
        const id_str = try pg.types.UUID.toString(id_bytes);
        const row_url = try row.get([]const u8, 1);
        const profile = try row.get([]const u8, 2);
        const ran_at_us = try row.get(i64, 3);
        const scores = try row.get([]const u8, 4);

        try list.append(allocator, AuditRunSummary{
            .id = try allocator.dupe(u8, &id_str),
            .url = try allocator.dupe(u8, row_url),
            .profile = try allocator.dupe(u8, profile),
            .ran_at_us = ran_at_us,
            .scores_json = try allocator.dupe(u8, scores),
            .allocator = allocator,
        });
    }
    return list.toOwnedSlice(allocator);
}

test "AuditRunSummary deinit" {
    const allocator = std.testing.allocator;
    const row = AuditRunSummary{
        .id = try allocator.dupe(u8, "run-uuid"),
        .url = try allocator.dupe(u8, "https://example.com"),
        .profile = try allocator.dupe(u8, "desktop"),
        .ran_at_us = 1_700_000_000_000_000,
        .scores_json = try allocator.dupe(u8, "{\"performance\":90}"),
        .allocator = allocator,
    };
    row.deinit();
}
