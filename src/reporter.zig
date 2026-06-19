const std = @import("std");
const scorer_mod = @import("auditor/scorer.zig");

// ── types ─────────────────────────────────────────────────────────────────────

pub const IssueRecord = struct {
    url: []const u8,
    category: scorer_mod.Category,
    rule_id: []const u8,
    severity: scorer_mod.Severity,
    detail: []const u8,
};

// ── derive records ────────────────────────────────────────────────────────────

pub fn issueRecordsFrom(
    url: []const u8,
    findings: []const scorer_mod.Finding,
    allocator: std.mem.Allocator,
) ![]IssueRecord {
    var records: std.ArrayList(IssueRecord) = .empty;
    errdefer records.deinit(allocator);
    for (findings) |f| {
        try records.append(allocator, .{
            .url = url,
            .category = f.category,
            .rule_id = f.rule_id,
            .severity = f.severity,
            .detail = f.detail,
        });
    }
    return records.toOwnedSlice(allocator);
}

// ── publish to GitHub Issues ──────────────────────────────────────────────────

pub fn publishIssues(records: []const IssueRecord, io: std.Io, allocator: std.mem.Allocator) !void {
    for (records) |rec| {
        const title = try std.fmt.allocPrint(
            allocator,
            "[sol-audit] {s} @ {s}",
            .{ rec.rule_id, rec.url },
        );
        defer allocator.free(title);

        if (try issueExists(title, io, allocator)) continue;

        const body = try std.fmt.allocPrint(
            allocator,
            "**Category**: {s}\n**Severity**: {s}\n\n{s}\n\n---\n*Rule ID*: `{s}`",
            .{ @tagName(rec.category), @tagName(rec.severity), rec.detail, rec.rule_id },
        );
        defer allocator.free(body);

        const argv = [_][]const u8{ "gh", "issue", "create", "--title", title, "--body", body };
        const result = try std.process.run(allocator, io, .{ .argv = &argv });
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }
}

// issueExists checks open issues for a matching title using gh CLI.
// Matches by searching the JSON title list output for the exact title string.
fn issueExists(title: []const u8, io: std.Io, allocator: std.mem.Allocator) !bool {
    const argv = [_][]const u8{ "gh", "issue", "list", "--state", "open", "--json", "title", "--limit", "500" };
    const result = try std.process.run(allocator, io, .{ .argv = &argv });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    return std.mem.indexOf(u8, result.stdout, title) != null;
}

// ── tests ─────────────────────────────────────────────────────────────────────

test "IssueRecord has url, category, rule_id, severity, detail fields" {
    const rec = IssueRecord{
        .url = "https://example.com",
        .category = .accessibility,
        .rule_id = "a11y_missing_lang",
        .severity = .critical,
        .detail = "html element missing lang attribute",
    };
    try std.testing.expectEqualStrings("https://example.com", rec.url);
    try std.testing.expectEqual(scorer_mod.Category.accessibility, rec.category);
    try std.testing.expectEqualStrings("a11y_missing_lang", rec.rule_id);
    try std.testing.expectEqual(scorer_mod.Severity.critical, rec.severity);
}

test "issueRecordsFrom returns empty slice when no findings" {
    const allocator = std.testing.allocator;
    const records = try issueRecordsFrom("https://example.com", &.{}, allocator);
    defer allocator.free(records);
    try std.testing.expectEqual(@as(usize, 0), records.len);
}

test "issueRecordsFrom returns one record per finding with correct url" {
    const allocator = std.testing.allocator;
    const findings = [_]scorer_mod.Finding{
        .{
            .rule_id = "a11y_missing_lang",
            .category = .accessibility,
            .severity = .critical,
            .detail = "html element missing lang attribute",
        },
        .{
            .rule_id = "bp_missing_https",
            .category = .best_practices,
            .severity = .critical,
            .detail = "page served over HTTP",
        },
    };
    const records = try issueRecordsFrom("https://example.com", &findings, allocator);
    defer allocator.free(records);
    try std.testing.expectEqual(@as(usize, 2), records.len);
    try std.testing.expectEqualStrings("https://example.com", records[0].url);
    try std.testing.expectEqualStrings("a11y_missing_lang", records[0].rule_id);
    try std.testing.expectEqualStrings("https://example.com", records[1].url);
    try std.testing.expectEqualStrings("bp_missing_https", records[1].rule_id);
}

test "issueRecordsFrom copies category and severity from findings" {
    const allocator = std.testing.allocator;
    const findings = [_]scorer_mod.Finding{
        .{
            .rule_id = "seo_missing_title",
            .category = .seo,
            .severity = .critical,
            .detail = "page has no title",
        },
    };
    const records = try issueRecordsFrom("https://example.com", &findings, allocator);
    defer allocator.free(records);
    try std.testing.expectEqual(scorer_mod.Category.seo, records[0].category);
    try std.testing.expectEqual(scorer_mod.Severity.critical, records[0].severity);
}
