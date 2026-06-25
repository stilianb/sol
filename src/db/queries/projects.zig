const std = @import("std");
const pg = @import("pg");

pub const ProjectRow = struct {
    id: []const u8,
    name: []const u8,
    primary_url: []const u8,
    competitor_urls: []const u8,
    user_id: []const u8,
    status: []const u8,
    archived: bool,
    allocator: std.mem.Allocator,

    pub fn deinit(self: ProjectRow) void {
        self.allocator.free(self.id);
        self.allocator.free(self.name);
        self.allocator.free(self.primary_url);
        self.allocator.free(self.competitor_urls);
        self.allocator.free(self.user_id);
        self.allocator.free(self.status);
    }
};

fn rowToProject(row: anytype, allocator: std.mem.Allocator) !ProjectRow {
    const id_bytes = try row.get([]const u8, 0);
    const id_str = try pg.types.UUID.toString(id_bytes);
    const name = try row.get([]const u8, 1);
    const primary_url = try row.get([]const u8, 2);
    const competitor_urls = try row.get([]const u8, 3);
    const user_id_bytes = try row.get([]const u8, 4);
    const user_id_str = try pg.types.UUID.toString(user_id_bytes);
    const status = try row.get([]const u8, 5);
    const archived = try row.get(bool, 6);
    return ProjectRow{
        .id = try allocator.dupe(u8, &id_str),
        .name = try allocator.dupe(u8, name),
        .primary_url = try allocator.dupe(u8, primary_url),
        .competitor_urls = try allocator.dupe(u8, competitor_urls),
        .user_id = try allocator.dupe(u8, &user_id_str),
        .status = try allocator.dupe(u8, status),
        .archived = archived,
        .allocator = allocator,
    };
}

const SEL = "id, name, primary_url, competitor_urls::text, user_id, status, archived";

pub fn create(
    pool: *pg.Pool,
    name: []const u8,
    primary_url: []const u8,
    competitor_urls_json: []const u8,
    user_id: []const u8,
    allocator: std.mem.Allocator,
) !ProjectRow {
    var conn = try pool.acquire();
    defer conn.release();

    var row_opt = try conn.row(
        "INSERT INTO projects (name, primary_url, competitor_urls, user_id) VALUES ($1, $2, $3::jsonb, $4::uuid) RETURNING " ++ SEL,
        .{ name, primary_url, competitor_urls_json, user_id },
    );
    if (row_opt) |*row| {
        defer row.deinit() catch {};
        return rowToProject(row, allocator);
    }
    return error.InsertFailed;
}

pub fn listByUser(
    pool: *pg.Pool,
    user_id: []const u8,
    allocator: std.mem.Allocator,
) ![]ProjectRow {
    var conn = try pool.acquire();
    defer conn.release();

    var result = try conn.query(
        "SELECT " ++ SEL ++ " FROM projects WHERE user_id = $1::uuid AND archived = FALSE ORDER BY created_at DESC",
        .{user_id},
    );
    defer result.deinit();

    var list: std.ArrayList(ProjectRow) = .empty;
    errdefer {
        for (list.items) |r| r.deinit();
        list.deinit(allocator);
    }

    while (try result.next()) |row| {
        const p = try rowToProject(row, allocator);
        try list.append(allocator, p);
    }
    return list.toOwnedSlice(allocator);
}

pub fn findById(
    pool: *pg.Pool,
    id: []const u8,
    user_id: []const u8,
    allocator: std.mem.Allocator,
) !?ProjectRow {
    var conn = try pool.acquire();
    defer conn.release();

    var row_opt = try conn.row(
        "SELECT " ++ SEL ++ " FROM projects WHERE id = $1::uuid AND user_id = $2::uuid AND archived = FALSE",
        .{ id, user_id },
    );
    if (row_opt) |*row| {
        defer row.deinit() catch {};
        return try rowToProject(row, allocator);
    }
    return null;
}

pub fn archive(pool: *pg.Pool, id: []const u8, user_id: []const u8) !void {
    var conn = try pool.acquire();
    defer conn.release();
    _ = try conn.exec(
        "UPDATE projects SET archived = TRUE, updated_at = NOW() WHERE id = $1::uuid AND user_id = $2::uuid",
        .{ id, user_id },
    );
}

pub fn delete(pool: *pg.Pool, id: []const u8, user_id: []const u8) !void {
    var conn = try pool.acquire();
    defer conn.release();
    _ = try conn.exec(
        "DELETE FROM projects WHERE id = $1::uuid AND user_id = $2::uuid",
        .{ id, user_id },
    );
}

test "ProjectRow deinit" {
    const allocator = std.testing.allocator;
    const row = ProjectRow{
        .id = try allocator.dupe(u8, "proj-uuid"),
        .name = try allocator.dupe(u8, "My Project"),
        .primary_url = try allocator.dupe(u8, "https://example.com"),
        .competitor_urls = try allocator.dupe(u8, "[]"),
        .user_id = try allocator.dupe(u8, "user-uuid"),
        .status = try allocator.dupe(u8, "draft"),
        .archived = false,
        .allocator = allocator,
    };
    row.deinit();
}
