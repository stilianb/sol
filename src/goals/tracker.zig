const std = @import("std");
const Io = std.Io;
const audit_mod = @import("../audit.zig");
const keywords_mod = @import("../auditor/keywords.zig");
const scorer_mod = @import("../auditor/scorer.zig");
const goals_mod = @import("goals.zig");

// ── types ─────────────────────────────────────────────────────────────────────

pub const PageResult = struct {
    url: []const u8,
    http_status: u16,
    scores: scorer_mod.Scores,
    keyword_coverages: []keywords_mod.KeywordCoverage,
    allocator: std.mem.Allocator,

    pub fn deinit(self: PageResult) void {
        self.allocator.free(self.url);
        for (self.keyword_coverages) |kc| kc.deinit();
        self.allocator.free(self.keyword_coverages);
    }
};

pub const GoalsReport = struct {
    pages: []PageResult,
    allocator: std.mem.Allocator,

    pub fn deinit(self: GoalsReport) void {
        for (self.pages) |pg| pg.deinit();
        self.allocator.free(self.pages);
    }
};

// ── run ───────────────────────────────────────────────────────────────────────

pub fn run(
    goals: goals_mod.GoalsFile,
    profile: audit_mod.AuditProfile,
    io: Io,
    allocator: std.mem.Allocator,
) !GoalsReport {
    var results: std.ArrayList(PageResult) = .empty;
    errdefer {
        for (results.items) |pg| pg.deinit();
        results.deinit(allocator);
    }

    for (goals.pages) |pg| {
        const report = audit_mod.run(pg.url, profile, pg.keywords, io, allocator) catch |err| {
            std.debug.print("warning: audit failed for {s}: {}\n", .{ pg.url, err });
            continue;
        };
        defer report.deinit();

        const url = try allocator.dupe(u8, report.url);
        errdefer allocator.free(url);

        const kcs = try copyKeywordCoverages(report.keyword_coverages, allocator);
        errdefer {
            for (kcs) |kc| kc.deinit();
            allocator.free(kcs);
        }

        try results.append(allocator, .{
            .url = url,
            .http_status = @intFromEnum(report.status),
            .scores = report.score_result.scores,
            .keyword_coverages = kcs,
            .allocator = allocator,
        });
    }

    return .{ .pages = try results.toOwnedSlice(allocator), .allocator = allocator };
}

fn copyKeywordCoverages(
    src: []const keywords_mod.KeywordCoverage,
    allocator: std.mem.Allocator,
) ![]keywords_mod.KeywordCoverage {
    const dst = try allocator.alloc(keywords_mod.KeywordCoverage, src.len);
    var filled: usize = 0;
    errdefer {
        for (dst[0..filled]) |kc| kc.deinit();
        allocator.free(dst);
    }
    for (src) |kc| {
        dst[filled] = .{
            .keyword = try allocator.dupe(u8, kc.keyword),
            .in_title = kc.in_title,
            .in_h1 = kc.in_h1,
            .in_description = kc.in_description,
            .density_permille = kc.density_permille,
            .coverage_score = kc.coverage_score,
            .allocator = allocator,
        };
        filled += 1;
    }
    return dst;
}

// ── renderJson ────────────────────────────────────────────────────────────────

fn jsonStr(out: *Io.Writer, s: []const u8) !void {
    try out.print("\"", .{});
    for (s) |ch| {
        switch (ch) {
            '"' => try out.print("\\\"", .{}),
            '\\' => try out.print("\\\\", .{}),
            '\n' => try out.print("\\n", .{}),
            '\r' => try out.print("\\r", .{}),
            '\t' => try out.print("\\t", .{}),
            else => try out.print("{c}", .{ch}),
        }
    }
    try out.print("\"", .{});
}

pub fn renderJson(report: GoalsReport, out: *Io.Writer) !void {
    try out.print("{{\"pages\":[", .{});
    for (report.pages, 0..) |pg, pi| {
        if (pi > 0) try out.print(",", .{});
        try out.print("{{\"url\":", .{});
        try jsonStr(out, pg.url);
        try out.print(",\"status\":{d}", .{pg.http_status});
        try out.print(",\"scores\":{{", .{});
        try out.print("\"performance\":{d}", .{pg.scores.performance});
        try out.print(",\"accessibility\":{d}", .{pg.scores.accessibility});
        try out.print(",\"best_practices\":{d}", .{pg.scores.best_practices});
        try out.print(",\"seo\":{d}", .{pg.scores.seo});
        try out.print(",\"gdpr\":{d}", .{pg.scores.gdpr});
        try out.print(",\"keyword\":{d}", .{pg.scores.keyword});
        try out.print(",\"aeo\":{d}", .{pg.scores.aeo});
        try out.print("}}", .{});
        try out.print(",\"keyword_coverage\":[", .{});
        for (pg.keyword_coverages, 0..) |kc, ki| {
            if (ki > 0) try out.print(",", .{});
            try out.print("{{\"keyword\":", .{});
            try jsonStr(out, kc.keyword);
            try out.print(",\"in_title\":{},\"in_h1\":{},\"in_description\":{},\"density_permille\":{d},\"coverage_score\":{d}}}", .{
                kc.in_title, kc.in_h1, kc.in_description, kc.density_permille, kc.coverage_score,
            });
        }
        try out.print("]}}", .{});
    }
    try out.print("]}}\n", .{});
}

// ── tests ─────────────────────────────────────────────────────────────────────

test "renderJson empty report produces valid JSON" {
    var buf: [256]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    const report = GoalsReport{ .pages = &.{}, .allocator = std.testing.allocator };
    try renderJson(report, &w);
    const json = std.Io.Writer.buffered(&w);
    try std.testing.expectEqualStrings("{\"pages\":[]}\n", json);
}

test "renderJson includes url and status for each page" {
    const allocator = std.testing.allocator;
    const kcs = try allocator.alloc(keywords_mod.KeywordCoverage, 0);
    const pages = try allocator.alloc(PageResult, 1);
    pages[0] = .{
        .url = try allocator.dupe(u8, "https://example.com"),
        .http_status = 200,
        .scores = .{
            .performance = 85,
            .accessibility = 90,
            .best_practices = 95,
            .seo = 80,
            .gdpr = 100,
            .keyword = 75,
            .aeo = 60,
        },
        .keyword_coverages = kcs,
        .allocator = allocator,
    };
    const report = GoalsReport{ .pages = pages, .allocator = allocator };
    defer report.deinit();

    var buf: [512]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try renderJson(report, &w);
    const json = std.Io.Writer.buffered(&w);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"url\":\"https://example.com\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"status\":200") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"performance\":85") != null);
}
