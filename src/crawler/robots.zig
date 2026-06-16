const std = @import("std");

// ── types ─────────────────────────────────────────────────────────────────────

pub const Rules = struct {
    sitemaps: []const []const u8,
    disallowed: []const []const u8,
    allowed: []const []const u8,
    crawl_delay_ms: u64,
    allocator: std.mem.Allocator,

    pub fn deinit(self: Rules) void {
        for (self.sitemaps) |s| self.allocator.free(s);
        self.allocator.free(self.sitemaps);
        for (self.disallowed) |s| self.allocator.free(s);
        self.allocator.free(self.disallowed);
        for (self.allowed) |s| self.allocator.free(s);
        self.allocator.free(self.allowed);
    }

    pub fn isAllowed(self: Rules, path: []const u8) bool {
        var best_disallow_len: usize = 0;
        var best_allow_len: usize = 0;

        for (self.disallowed) |rule| {
            if (rule.len == 0) continue;
            if (std.mem.startsWith(u8, path, rule) and rule.len > best_disallow_len)
                best_disallow_len = rule.len;
        }
        if (best_disallow_len == 0) return true;

        for (self.allowed) |rule| {
            if (rule.len == 0) continue;
            if (std.mem.startsWith(u8, path, rule) and rule.len > best_allow_len)
                best_allow_len = rule.len;
        }

        return best_allow_len >= best_disallow_len;
    }
};

pub fn parse(text: []const u8, user_agent: []const u8, allocator: std.mem.Allocator) !Rules {
    var sitemaps: std.ArrayList([]const u8) = .empty;
    var wildcard_disallow: std.ArrayList([]const u8) = .empty;
    var wildcard_allow: std.ArrayList([]const u8) = .empty;
    var specific_disallow: std.ArrayList([]const u8) = .empty;
    var specific_allow: std.ArrayList([]const u8) = .empty;
    var crawl_delay_ms: u64 = 0;

    const Block = enum { none, wildcard, specific, other };
    var block: Block = .none;
    var found_specific = false;

    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        if (splitDirective(line)) |kv| {
            const key = kv[0];
            const val = kv[1];

            if (std.ascii.eqlIgnoreCase(key, "user-agent")) {
                if (std.ascii.eqlIgnoreCase(val, user_agent)) {
                    block = .specific;
                    found_specific = true;
                } else if (std.mem.eql(u8, val, "*")) {
                    block = .wildcard;
                } else {
                    block = .other;
                }
            } else if (std.ascii.eqlIgnoreCase(key, "sitemap")) {
                try sitemaps.append(allocator, try allocator.dupe(u8, val));
            } else if (std.ascii.eqlIgnoreCase(key, "disallow")) {
                switch (block) {
                    .specific => try specific_disallow.append(allocator, try allocator.dupe(u8, val)),
                    .wildcard => try wildcard_disallow.append(allocator, try allocator.dupe(u8, val)),
                    else => {},
                }
            } else if (std.ascii.eqlIgnoreCase(key, "allow")) {
                switch (block) {
                    .specific => try specific_allow.append(allocator, try allocator.dupe(u8, val)),
                    .wildcard => try wildcard_allow.append(allocator, try allocator.dupe(u8, val)),
                    else => {},
                }
            } else if (std.ascii.eqlIgnoreCase(key, "crawl-delay")) {
                if (block == .wildcard or block == .specific) {
                    const secs = std.fmt.parseFloat(f64, val) catch continue;
                    crawl_delay_ms = @intFromFloat(secs * 1000.0);
                }
            }
        }
    }

    // prefer specific agent rules; fall back to wildcard
    const use_specific = found_specific;
    var disallow_list = if (use_specific) specific_disallow else wildcard_disallow;
    var allow_list = if (use_specific) specific_allow else wildcard_allow;

    // free whichever list we're not using
    if (use_specific) {
        for (wildcard_disallow.items) |s| allocator.free(s);
        wildcard_disallow.deinit(allocator);
        for (wildcard_allow.items) |s| allocator.free(s);
        wildcard_allow.deinit(allocator);
    } else {
        for (specific_disallow.items) |s| allocator.free(s);
        specific_disallow.deinit(allocator);
        for (specific_allow.items) |s| allocator.free(s);
        specific_allow.deinit(allocator);
    }

    return .{
        .sitemaps = try sitemaps.toOwnedSlice(allocator),
        .disallowed = try disallow_list.toOwnedSlice(allocator),
        .allowed = try allow_list.toOwnedSlice(allocator),
        .crawl_delay_ms = crawl_delay_ms,
        .allocator = allocator,
    };
}

fn splitDirective(line: []const u8) ?[2][]const u8 {
    const colon = std.mem.indexOf(u8, line, ":") orelse return null;
    const key = std.mem.trim(u8, line[0..colon], " \t");
    const val = std.mem.trim(u8, line[colon + 1 ..], " \t");
    return .{ key, val };
}

// ── tests ─────────────────────────────────────────────────────────────────────

const ROBOTS_TXT =
    \\User-agent: *
    \\Disallow: /admin
    \\Disallow: /private/
    \\Allow: /admin/public
    \\Crawl-delay: 2
    \\
    \\User-agent: sol
    \\Disallow: /staging
    \\
    \\Sitemap: https://example.com/sitemap.xml
    \\Sitemap: https://example.com/news-sitemap.xml
;

test "parse extracts sitemap URLs" {
    const rules = try parse(ROBOTS_TXT, "sol", std.testing.allocator);
    defer rules.deinit();

    try std.testing.expectEqual(@as(usize, 2), rules.sitemaps.len);
    try std.testing.expectEqualStrings("https://example.com/sitemap.xml", rules.sitemaps[0]);
    try std.testing.expectEqualStrings("https://example.com/news-sitemap.xml", rules.sitemaps[1]);
}

test "parse uses specific agent rules over wildcard" {
    const rules = try parse(ROBOTS_TXT, "sol", std.testing.allocator);
    defer rules.deinit();

    // sol block has /staging — not the wildcard /admin, /private/
    try std.testing.expectEqual(@as(usize, 1), rules.disallowed.len);
    try std.testing.expectEqualStrings("/staging", rules.disallowed[0]);
}

test "parse falls back to wildcard when agent not found" {
    const rules = try parse(ROBOTS_TXT, "unknown-bot", std.testing.allocator);
    defer rules.deinit();

    try std.testing.expectEqual(@as(usize, 2), rules.disallowed.len);
    try std.testing.expectEqualStrings("/admin", rules.disallowed[0]);
    try std.testing.expectEqualStrings("/private/", rules.disallowed[1]);
}

test "parse extracts allow rules from wildcard block" {
    const rules = try parse(ROBOTS_TXT, "unknown-bot", std.testing.allocator);
    defer rules.deinit();

    try std.testing.expectEqual(@as(usize, 1), rules.allowed.len);
    try std.testing.expectEqualStrings("/admin/public", rules.allowed[0]);
}

test "parse extracts crawl delay in ms" {
    const rules = try parse(ROBOTS_TXT, "unknown-bot", std.testing.allocator);
    defer rules.deinit();

    try std.testing.expectEqual(@as(u64, 2000), rules.crawl_delay_ms);
}

test "parse returns empty rules for empty robots.txt" {
    const rules = try parse("", "*", std.testing.allocator);
    defer rules.deinit();

    try std.testing.expectEqual(@as(usize, 0), rules.sitemaps.len);
    try std.testing.expectEqual(@as(usize, 0), rules.disallowed.len);
}

test "isAllowed returns false for disallowed path" {
    const rules = try parse(ROBOTS_TXT, "unknown-bot", std.testing.allocator);
    defer rules.deinit();

    try std.testing.expect(!rules.isAllowed("/admin/secret"));
    try std.testing.expect(!rules.isAllowed("/private/data"));
}

test "isAllowed allow overrides disallow for more specific path" {
    const rules = try parse(ROBOTS_TXT, "unknown-bot", std.testing.allocator);
    defer rules.deinit();

    // /admin disallowed but /admin/public explicitly allowed
    try std.testing.expect(rules.isAllowed("/admin/public"));
}

test "isAllowed returns true for non-disallowed path" {
    const rules = try parse(ROBOTS_TXT, "unknown-bot", std.testing.allocator);
    defer rules.deinit();

    try std.testing.expect(rules.isAllowed("/products"));
    try std.testing.expect(rules.isAllowed("/"));
}

test "isAllowed returns true when rules are empty" {
    const rules = try parse("", "*", std.testing.allocator);
    defer rules.deinit();

    try std.testing.expect(rules.isAllowed("/anything"));
}
