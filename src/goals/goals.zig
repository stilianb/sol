const std = @import("std");
const Io = std.Io;

// ── types ─────────────────────────────────────────────────────────────────────

pub const PageGoal = struct {
    url: []const u8,
    keywords: []const []const u8,
};

pub const GoalsFile = struct {
    pages: []PageGoal,
    allocator: std.mem.Allocator,

    pub fn deinit(self: GoalsFile) void {
        for (self.pages) |pg| {
            self.allocator.free(pg.url);
            for (pg.keywords) |kw| self.allocator.free(kw);
            self.allocator.free(pg.keywords);
        }
        self.allocator.free(self.pages);
    }
};

// ── load / discover ───────────────────────────────────────────────────────────

const default_filename = "sol-goals.json";

/// Auto-discover `sol-goals.json` in the current working directory.
/// Returns null if the file does not exist.
pub fn discover(io: Io, allocator: std.mem.Allocator) !?GoalsFile {
    const cwd = std.Io.Dir.cwd();
    const json_text = cwd.readFileAlloc(io, default_filename, allocator, .unlimited) catch |err| {
        if (err == error.FileNotFound) return null;
        return err;
    };
    defer allocator.free(json_text);
    return try parseGoals(json_text, allocator);
}

/// Load a goals file from an explicit path (relative to cwd).
pub fn load(path: []const u8, io: Io, allocator: std.mem.Allocator) !GoalsFile {
    const cwd = std.Io.Dir.cwd();
    const json_text = try cwd.readFileAlloc(io, path, allocator, .unlimited);
    defer allocator.free(json_text);
    return try parseGoals(json_text, allocator);
}

/// Parse a goals JSON string. Public for testing.
pub fn parseGoals(json_text: []const u8, allocator: std.mem.Allocator) !GoalsFile {
    const PageSchema = struct {
        url: []const u8,
        keywords: []const []const u8,
    };
    const GoalsSchema = struct {
        pages: []const PageSchema,
    };

    const parsed = try std.json.parseFromSlice(GoalsSchema, allocator, json_text, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    const pages = try allocator.alloc(PageGoal, parsed.value.pages.len);
    var filled: usize = 0;
    errdefer {
        for (pages[0..filled]) |pg| {
            allocator.free(pg.url);
            for (pg.keywords) |kw| allocator.free(kw);
            allocator.free(pg.keywords);
        }
        allocator.free(pages);
    }

    for (parsed.value.pages) |p| {
        const url = try allocator.dupe(u8, p.url);
        errdefer allocator.free(url);

        const keywords = try allocator.alloc([]const u8, p.keywords.len);
        var kw_filled: usize = 0;
        errdefer {
            for (keywords[0..kw_filled]) |kw| allocator.free(kw);
            allocator.free(keywords);
        }
        for (p.keywords) |kw| {
            keywords[kw_filled] = try allocator.dupe(u8, kw);
            kw_filled += 1;
        }

        pages[filled] = .{ .url = url, .keywords = keywords };
        filled += 1;
    }

    return .{ .pages = pages, .allocator = allocator };
}

// ── tests ─────────────────────────────────────────────────────────────────────

test "parseGoals parses pages and keywords (mobile fixture)" {
    const json =
        \\{"pages":[{"url":"https://example.com","keywords":["audit tool","seo checker"]}]}
    ;
    const goals = try parseGoals(json, std.testing.allocator);
    defer goals.deinit();
    try std.testing.expectEqual(@as(usize, 1), goals.pages.len);
    try std.testing.expectEqualStrings("https://example.com", goals.pages[0].url);
    try std.testing.expectEqual(@as(usize, 2), goals.pages[0].keywords.len);
    try std.testing.expectEqualStrings("audit tool", goals.pages[0].keywords[0]);
    try std.testing.expectEqualStrings("seo checker", goals.pages[0].keywords[1]);
}

test "parseGoals handles empty pages array" {
    const json = \\{"pages":[]}
    ;
    const goals = try parseGoals(json, std.testing.allocator);
    defer goals.deinit();
    try std.testing.expectEqual(@as(usize, 0), goals.pages.len);
}

test "parseGoals ignores unknown top-level fields" {
    const json =
        \\{"pages":[],"version":"1.0","description":"my goals"}
    ;
    const goals = try parseGoals(json, std.testing.allocator);
    defer goals.deinit();
    try std.testing.expectEqual(@as(usize, 0), goals.pages.len);
}

test "parseGoals handles multiple pages" {
    const json =
        \\{"pages":[
        \\  {"url":"https://example.com/a","keywords":["kw1"]},
        \\  {"url":"https://example.com/b","keywords":["kw2","kw3"]}
        \\]}
    ;
    const goals = try parseGoals(json, std.testing.allocator);
    defer goals.deinit();
    try std.testing.expectEqual(@as(usize, 2), goals.pages.len);
    try std.testing.expectEqualStrings("https://example.com/a", goals.pages[0].url);
    try std.testing.expectEqual(@as(usize, 1), goals.pages[0].keywords.len);
    try std.testing.expectEqual(@as(usize, 2), goals.pages[1].keywords.len);
}
