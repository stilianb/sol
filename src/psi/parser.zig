const std = @import("std");
const types = @import("types.zig");

pub const PsiData = types.PsiData;

const PSI_BASE = "https://www.googleapis.com/pagespeedonline/v5/runPagespeed";

/// Extract PsiData from a raw PSI API v5 JSON response body.
pub fn parse(json_body: []const u8, strategy: []const u8, allocator: std.mem.Allocator) !PsiData {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_body, .{});
    defer parsed.deinit();
    const root = parsed.value;

    const strategy_owned = try allocator.dupe(u8, strategy);
    errdefer allocator.free(strategy_owned);

    // Lighthouse result
    const lr = root.object.get("lighthouseResult") orelse return error.MissingLighthouseResult;
    const cats = lr.object.get("categories") orelse return error.MissingCategories;

    const lh_perf  = extractScore(cats, "performance");
    const lh_a11y  = extractScore(cats, "accessibility");
    const lh_bp    = extractScore(cats, "best-practices");
    const lh_seo   = extractScore(cats, "seo");

    // audits → metrics
    const audits = lr.object.get("audits");
    const lcp_ms   = extractMetricMs(audits, "largest-contentful-paint");
    const fcp_ms   = extractMetricMs(audits, "first-contentful-paint");
    const tbt_ms   = extractMetricMs(audits, "total-blocking-time");
    const si_ms    = extractMetricMs(audits, "speed-index");
    const inp_ms   = extractMetricMs(audits, "interaction-to-next-paint");
    const cls      = extractCls(audits);

    return .{
        .strategy = strategy_owned,
        .lcp_ms = lcp_ms,
        .fcp_ms = fcp_ms,
        .cls_score = cls,
        .tbt_ms = tbt_ms,
        .speed_index_ms = si_ms,
        .inp_ms = inp_ms,
        .lighthouse_performance = lh_perf,
        .lighthouse_accessibility = lh_a11y,
        .lighthouse_best_practices = lh_bp,
        .lighthouse_seo = lh_seo,
        .allocator = allocator,
    };
}

fn extractScore(cats: std.json.Value, key: []const u8) ?u8 {
    const cat = cats.object.get(key) orelse return null;
    const score = cat.object.get("score") orelse return null;
    return switch (score) {
        .float => |f| @intFromFloat(@round(f * 100.0)),
        .integer => |n| @intCast(n),
        else => null,
    };
}

fn extractMetricMs(audits: ?std.json.Value, key: []const u8) ?u64 {
    const a = audits orelse return null;
    const audit = a.object.get(key) orelse return null;
    const num = audit.object.get("numericValue") orelse return null;
    return switch (num) {
        .float => |f| @intFromFloat(@round(f)),
        .integer => |n| @intCast(n),
        else => null,
    };
}

fn extractCls(audits: ?std.json.Value) ?f32 {
    const a = audits orelse return null;
    const audit = a.object.get("cumulative-layout-shift") orelse return null;
    const num = audit.object.get("numericValue") orelse return null;
    return switch (num) {
        .float => |f| @floatCast(f),
        .integer => |n| @floatFromInt(n),
        else => null,
    };
}

// ── tests ─────────────────────────────────────────────────────────────────────

const FIXTURE =
    \\{
    \\  "lighthouseResult": {
    \\    "categories": {
    \\      "performance":    {"score": 0.72},
    \\      "accessibility":  {"score": 0.88},
    \\      "best-practices": {"score": 0.95},
    \\      "seo":            {"score": 0.91}
    \\    },
    \\    "audits": {
    \\      "largest-contentful-paint":  {"numericValue": 2480.0},
    \\      "first-contentful-paint":    {"numericValue": 1200.0},
    \\      "total-blocking-time":       {"numericValue": 140.0},
    \\      "speed-index":               {"numericValue": 3300.0},
    \\      "cumulative-layout-shift":   {"numericValue": 0.05}
    \\    }
    \\  }
    \\}
;

test "parse extracts lighthouse scores from fixture" {
    const allocator = std.testing.allocator;
    const data = try parse(FIXTURE, "mobile", allocator);
    defer data.deinit();
    try std.testing.expectEqual(@as(?u8, 72), data.lighthouse_performance);
    try std.testing.expectEqual(@as(?u8, 88), data.lighthouse_accessibility);
    try std.testing.expectEqual(@as(?u8, 95), data.lighthouse_best_practices);
    try std.testing.expectEqual(@as(?u8, 91), data.lighthouse_seo);
}

test "parse extracts CWV metrics from fixture" {
    const allocator = std.testing.allocator;
    const data = try parse(FIXTURE, "mobile", allocator);
    defer data.deinit();
    try std.testing.expectEqual(@as(?u64, 2480), data.lcp_ms);
    try std.testing.expectEqual(@as(?u64, 1200), data.fcp_ms);
    try std.testing.expectEqual(@as(?u64, 140), data.tbt_ms);
    try std.testing.expectEqual(@as(?u64, 3300), data.speed_index_ms);
    try std.testing.expect(data.cls_score != null);
    try std.testing.expect(data.cls_score.? < 0.1);
}

test "parse strategy stored correctly" {
    const allocator = std.testing.allocator;
    const data = try parse(FIXTURE, "desktop", allocator);
    defer data.deinit();
    try std.testing.expectEqualStrings("desktop", data.strategy);
}
