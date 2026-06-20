const std = @import("std");
const pool_mod = @import("../crawler/pool.zig");
const scorer_mod = @import("../auditor/scorer.zig");

pub const ProgressEvent = pool_mod.ProgressEvent;
pub const Scores = scorer_mod.Scores;

/// Compact per-page summary — passed to writePageEvent by handlers.
pub const PageSummary = struct {
    url: []const u8,
    http_status: u16,
    scores: Scores,
    finding_count: usize,
};

/// Aggregate sent as the final event when the crawl completes.
pub const DoneSummary = struct {
    total_pages: usize,
    total_findings: usize,
    critical_count: usize,
    warning_count: usize,
    info_count: usize,
};

// ── writers ───────────────────────────────────────────────────────────────────

pub fn writeProgressEvent(out: *std.Io.Writer, event: ProgressEvent) !void {
    try out.writeAll("event: progress\ndata: ");
    try out.print("{{\"phase\":\"{s}\",\"total_done\":{d},\"total_queued\":{d},\"runners\":[", .{
        @tagName(event.phase),
        event.total_done,
        event.total_queued,
    });
    for (event.runners, 0..) |r, i| {
        if (i > 0) try out.writeAll(",");
        try out.print(
            "{{\"id\":{d},\"status\":\"{s}\",\"pages_done\":{d},\"pages_failed\":{d},\"url\":\"{s}\"}}",
            .{ r.id, @tagName(r.status), r.pages_done, r.pages_failed, r.current_url },
        );
    }
    try out.writeAll("]}\n\n");
}

pub fn writePageEvent(out: *std.Io.Writer, summary: PageSummary) !void {
    try out.writeAll("event: page\ndata: ");
    try out.print(
        "{{\"url\":\"{s}\",\"status\":{d},\"scores\":{{" ++
            "\"performance\":{d},\"accessibility\":{d},\"best_practices\":{d}," ++
            "\"seo\":{d},\"gdpr\":{d},\"keyword\":{d},\"aeo\":{d}" ++
            "}},\"findings\":{d}}}\n\n",
        .{
            summary.url,
            summary.http_status,
            summary.scores.performance,
            summary.scores.accessibility,
            summary.scores.best_practices,
            summary.scores.seo,
            summary.scores.gdpr,
            summary.scores.keyword,
            summary.scores.aeo,
            summary.finding_count,
        },
    );
}

pub fn writeDoneEvent(out: *std.Io.Writer, summary: DoneSummary) !void {
    try out.writeAll("event: done\ndata: ");
    try out.print(
        "{{\"total_pages\":{d},\"total_findings\":{d},\"critical\":{d},\"warning\":{d},\"info\":{d}}}\n\n",
        .{
            summary.total_pages,
            summary.total_findings,
            summary.critical_count,
            summary.warning_count,
            summary.info_count,
        },
    );
}

// ── tests ─────────────────────────────────────────────────────────────────────

test "writeProgressEvent produces valid SSE format" {
    var buf: [1024]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try writeProgressEvent(&w, .{
        .phase = .round_start,
        .runners = &.{},
        .total_done = 0,
        .total_queued = 3,
    });
    const written = std.Io.Writer.buffered(&w);
    try std.testing.expect(std.mem.startsWith(u8, written, "event: progress\ndata: "));
    try std.testing.expect(std.mem.endsWith(u8, written, "\n\n"));
    try std.testing.expect(std.mem.indexOf(u8, written, "\"phase\":\"round_start\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "\"total_queued\":3") != null);
}

test "writePageEvent produces valid SSE format" {
    var buf: [1024]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try writePageEvent(&w, .{
        .url = "https://example.com",
        .http_status = 200,
        .scores = .{
            .performance = 90,
            .accessibility = 100,
            .best_practices = 95,
            .seo = 85,
            .gdpr = 100,
            .keyword = 80,
            .aeo = 75,
        },
        .finding_count = 3,
    });
    const written = std.Io.Writer.buffered(&w);
    try std.testing.expect(std.mem.startsWith(u8, written, "event: page\ndata: "));
    try std.testing.expect(std.mem.endsWith(u8, written, "\n\n"));
    try std.testing.expect(std.mem.indexOf(u8, written, "\"url\":\"https://example.com\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "\"findings\":3") != null);
}

test "writeDoneEvent produces valid SSE format" {
    var buf: [512]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try writeDoneEvent(&w, .{
        .total_pages = 5,
        .total_findings = 3,
        .critical_count = 1,
        .warning_count = 2,
        .info_count = 0,
    });
    const written = std.Io.Writer.buffered(&w);
    try std.testing.expect(std.mem.startsWith(u8, written, "event: done\ndata: "));
    try std.testing.expect(std.mem.endsWith(u8, written, "\n\n"));
    try std.testing.expect(std.mem.indexOf(u8, written, "\"total_pages\":5") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "\"critical\":1") != null);
}
