const std = @import("std");

pub const Route = enum { audit, crawl, health, auth_register, auth_login, auth_refresh, auth_logout, user_me, projects_list, projects_create, project_get, project_delete, project_audit, audit_runs, recommendations, not_found };

pub const AuditParams = struct {
    url: []const u8,
    keyword: ?[]const u8,
};

pub const CrawlParams = struct {
    url: []const u8,
    depth: usize,
    runners: usize,
    keyword: ?[]const u8,
};

pub const ParseError = error{MissingUrl};

pub fn matchRoute(target: []const u8) Route {
    const path = pathOf(target);
    if (std.mem.eql(u8, path, "/api/audit")) return .audit;
    if (std.mem.eql(u8, path, "/api/crawl")) return .crawl;
    if (std.mem.eql(u8, path, "/health")) return .health;
    if (std.mem.eql(u8, path, "/auth/register")) return .auth_register;
    if (std.mem.eql(u8, path, "/auth/login")) return .auth_login;
    if (std.mem.eql(u8, path, "/auth/refresh")) return .auth_refresh;
    if (std.mem.eql(u8, path, "/auth/logout")) return .auth_logout;
    if (std.mem.eql(u8, path, "/user/me")) return .user_me;
    if (std.mem.eql(u8, path, "/projects")) return .projects_list;
    if (std.mem.eql(u8, path, "/api/runs")) return .audit_runs;
    if (std.mem.eql(u8, path, "/api/recommendations")) return .recommendations;
    if (std.mem.startsWith(u8, path, "/projects/") and path.len > "/projects/".len) {
        if (std.mem.endsWith(u8, path, "/audit")) return .project_audit;
        return .project_get;
    }
    return .not_found;
}

pub fn parseAuditParams(target: []const u8) ParseError!AuditParams {
    const query = queryOf(target);
    const url = getParam(query, "url") orelse return error.MissingUrl;
    return .{ .url = url, .keyword = getParam(query, "keyword") };
}

pub fn parseCrawlParams(target: []const u8) ParseError!CrawlParams {
    const query = queryOf(target);
    const url = getParam(query, "url") orelse return error.MissingUrl;
    const depth = if (getParam(query, "depth")) |d| std.fmt.parseInt(usize, d, 10) catch 1 else 1;
    const runners = if (getParam(query, "runners")) |r| std.fmt.parseInt(usize, r, 10) catch 4 else 4;
    return .{ .url = url, .depth = depth, .runners = runners, .keyword = getParam(query, "keyword") };
}

fn pathOf(target: []const u8) []const u8 {
    return if (std.mem.indexOfScalar(u8, target, '?')) |i| target[0..i] else target;
}

fn queryOf(target: []const u8) []const u8 {
    return if (std.mem.indexOfScalar(u8, target, '?')) |i| target[i + 1 ..] else "";
}

fn getParam(query: []const u8, key: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, query, '&');
    while (it.next()) |pair| {
        const eq = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
        if (std.mem.eql(u8, pair[0..eq], key)) return pair[eq + 1 ..];
    }
    return null;
}

/// Extract the path segment after a known prefix.
/// "/projects/abc-123" with prefix "/projects/" → "abc-123"
/// Strips any trailing sub-path after the segment.
pub fn extractSegment(target: []const u8, prefix: []const u8) ?[]const u8 {
    const path = pathOf(target);
    if (!std.mem.startsWith(u8, path, prefix)) return null;
    const seg = path[prefix.len..];
    const end = std.mem.indexOfScalar(u8, seg, '/') orelse seg.len;
    return if (end > 0) seg[0..end] else null;
}

// ── percent-decode ────────────────────────────────────────────────────────────

/// Decode a percent-encoded query param value into `buf`. Returns written slice.
/// Decodes %XX sequences and converts + to space. Never exceeds buf.len.
pub fn percentDecodeInto(encoded: []const u8, buf: []u8) []u8 {
    var out: usize = 0;
    var i: usize = 0;
    while (i < encoded.len and out < buf.len) {
        if (encoded[i] == '%' and i + 2 < encoded.len) {
            const hi = std.fmt.charToDigit(encoded[i + 1], 16) catch 255;
            const lo = std.fmt.charToDigit(encoded[i + 2], 16) catch 255;
            if (hi < 16 and lo < 16) {
                buf[out] = hi * 16 + lo;
                out += 1;
                i += 3;
                continue;
            }
        } else if (encoded[i] == '+') {
            buf[out] = ' ';
            out += 1;
            i += 1;
            continue;
        }
        buf[out] = encoded[i];
        out += 1;
        i += 1;
    }
    return buf[0..out];
}

// ── tests ─────────────────────────────────────────────────────────────────────

test "percentDecodeInto decodes %XX sequences" {
    var buf: [256]u8 = undefined;
    const out = percentDecodeInto("https%3A%2F%2Fexample.com%2Fpath", &buf);
    try std.testing.expectEqualStrings("https://example.com/path", out);
}

test "percentDecodeInto converts + to space" {
    var buf: [64]u8 = undefined;
    const out = percentDecodeInto("site+audit+tool", &buf);
    try std.testing.expectEqualStrings("site audit tool", out);
}

test "percentDecodeInto passthrough for plain strings" {
    var buf: [64]u8 = undefined;
    const out = percentDecodeInto("https://example.com", &buf);
    try std.testing.expectEqualStrings("https://example.com", out);
}

test "percentDecodeInto full browser-encoded URL" {
    var buf: [256]u8 = undefined;
    const out = percentDecodeInto("https%3A%2F%2Fmogl.com", &buf);
    try std.testing.expectEqualStrings("https://mogl.com", out);
}

test "matchRoute /api/audit" {
    try std.testing.expectEqual(.audit, matchRoute("/api/audit"));
    try std.testing.expectEqual(.audit, matchRoute("/api/audit?url=https://x.com"));
}

test "matchRoute /api/crawl" {
    try std.testing.expectEqual(.crawl, matchRoute("/api/crawl"));
    try std.testing.expectEqual(.crawl, matchRoute("/api/crawl?url=https://x.com&depth=2"));
}

test "matchRoute /health" {
    try std.testing.expectEqual(.health, matchRoute("/health"));
}

test "matchRoute /projects" {
    try std.testing.expectEqual(.projects_list, matchRoute("/projects"));
    try std.testing.expectEqual(.project_get, matchRoute("/projects/abc-123"));
    try std.testing.expectEqual(.project_audit, matchRoute("/projects/abc-123/audit"));
}

test "matchRoute /api/runs and /api/recommendations" {
    try std.testing.expectEqual(.audit_runs, matchRoute("/api/runs"));
    try std.testing.expectEqual(.recommendations, matchRoute("/api/recommendations"));
}

test "extractSegment basic" {
    try std.testing.expectEqualStrings("abc-123", extractSegment("/projects/abc-123", "/projects/").?);
    try std.testing.expectEqualStrings("abc-123", extractSegment("/projects/abc-123/audit", "/projects/").?);
    try std.testing.expect(extractSegment("/other/abc", "/projects/") == null);
}

test "matchRoute unknown returns not_found" {
    try std.testing.expectEqual(.not_found, matchRoute("/"));
    try std.testing.expectEqual(.not_found, matchRoute("/api/scores"));
    try std.testing.expectEqual(.not_found, matchRoute("/favicon.ico"));
}

test "parseAuditParams extracts url" {
    const p = try parseAuditParams("/api/audit?url=https://example.com");
    try std.testing.expectEqualStrings("https://example.com", p.url);
    try std.testing.expectEqual(null, p.keyword);
}

test "parseAuditParams extracts keyword" {
    const p = try parseAuditParams("/api/audit?url=https://example.com&keyword=site+audit");
    try std.testing.expectEqualStrings("https://example.com", p.url);
    try std.testing.expectEqualStrings("site+audit", p.keyword.?);
}

test "parseAuditParams missing url returns error" {
    try std.testing.expectError(error.MissingUrl, parseAuditParams("/api/audit"));
    try std.testing.expectError(error.MissingUrl, parseAuditParams("/api/audit?keyword=foo"));
}

test "parseCrawlParams defaults depth=1 runners=4" {
    const p = try parseCrawlParams("/api/crawl?url=https://example.com");
    try std.testing.expectEqualStrings("https://example.com", p.url);
    try std.testing.expectEqual(@as(usize, 1), p.depth);
    try std.testing.expectEqual(@as(usize, 4), p.runners);
    try std.testing.expectEqual(null, p.keyword);
}

test "parseCrawlParams explicit depth and runners" {
    const p = try parseCrawlParams("/api/crawl?url=https://x.com&depth=3&runners=8");
    try std.testing.expectEqual(@as(usize, 3), p.depth);
    try std.testing.expectEqual(@as(usize, 8), p.runners);
}
