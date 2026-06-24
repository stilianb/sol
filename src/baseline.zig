const std = @import("std");
const audit_mod = @import("audit.zig");
const scorer_mod = @import("auditor/scorer.zig");

// ── types ─────────────────────────────────────────────────────────────────────

pub const ScoreDelta = struct {
    category: []const u8,
    before: u8,
    after: u8,

    pub fn regressed(self: ScoreDelta) bool {
        return self.before > self.after and (self.before - self.after) >= 5;
    }
};

pub const PageDiff = struct {
    url: []const u8,
    score_deltas: []ScoreDelta,
    introduced: [][]const u8,
    resolved: [][]const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: PageDiff) void {
        self.allocator.free(self.score_deltas);
        for (self.introduced) |s| self.allocator.free(s);
        self.allocator.free(self.introduced);
        for (self.resolved) |s| self.allocator.free(s);
        self.allocator.free(self.resolved);
    }
};

pub const DiffResult = struct {
    pages: []PageDiff,
    allocator: std.mem.Allocator,

    pub fn deinit(self: DiffResult) void {
        for (self.pages) |p| p.deinit();
        self.allocator.free(self.pages);
    }
};

// ── BaselineScores — minimal parsed view of one page from baseline JSON ───────

pub const BaselineScores = struct {
    url: []const u8,
    performance: u8,
    accessibility: u8,
    best_practices: u8,
    seo: u8,
    gdpr: u8,
    keyword: u8,
    aeo: u8,
    rule_ids: [][]const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: BaselineScores) void {
        self.allocator.free(self.url);
        for (self.rule_ids) |r| self.allocator.free(r);
        self.allocator.free(self.rule_ids);
    }
};

// ── parseBaselinePage — extract scores + rule_ids from one JSON object ────────

pub fn parseBaselinePage(json_text: []const u8, allocator: std.mem.Allocator) !BaselineScores {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_text, .{});
    defer parsed.deinit();
    const root = parsed.value;

    const url = try allocator.dupe(u8, root.object.get("url").?.string);
    errdefer allocator.free(url);

    const scores_obj = root.object.get("scores").?.object;
    const perf = @as(u8, @intCast(scores_obj.get("performance").?.integer));
    const a11y = @as(u8, @intCast(scores_obj.get("accessibility").?.integer));
    const bp   = @as(u8, @intCast(scores_obj.get("best_practices").?.integer));
    const seo  = @as(u8, @intCast(scores_obj.get("seo").?.integer));
    const gdpr = @as(u8, @intCast(scores_obj.get("gdpr").?.integer));
    const kw   = @as(u8, @intCast(scores_obj.get("keyword").?.integer));
    const aeo  = @as(u8, @intCast(scores_obj.get("aeo").?.integer));

    const findings_arr = root.object.get("findings").?.array;
    var rule_ids: std.ArrayList([]const u8) = .empty;
    errdefer { for (rule_ids.items) |r| allocator.free(r); rule_ids.deinit(allocator); }
    for (findings_arr.items) |f| {
        const rid = try allocator.dupe(u8, f.object.get("rule_id").?.string);
        try rule_ids.append(allocator, rid);
    }

    return .{
        .url = url,
        .performance = perf,
        .accessibility = a11y,
        .best_practices = bp,
        .seo = seo,
        .gdpr = gdpr,
        .keyword = kw,
        .aeo = aeo,
        .rule_ids = try rule_ids.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

// ── diffPage — compare fresh AuditReport against a baseline page ──────────────

pub fn diffPage(fresh: audit_mod.AuditReport, baseline: BaselineScores, allocator: std.mem.Allocator) !PageDiff {
    const cat_names = [_][]const u8{ "performance", "accessibility", "best_practices", "seo", "gdpr", "keyword", "aeo" };
    const fresh_vals = [_]u8{
        fresh.score_result.scores.performance,
        fresh.score_result.scores.accessibility,
        fresh.score_result.scores.best_practices,
        fresh.score_result.scores.seo,
        fresh.score_result.scores.gdpr,
        fresh.score_result.scores.keyword,
        fresh.score_result.scores.aeo,
    };
    const base_vals = [_]u8{
        baseline.performance, baseline.accessibility, baseline.best_practices,
        baseline.seo, baseline.gdpr, baseline.keyword, baseline.aeo,
    };

    var deltas = try allocator.alloc(ScoreDelta, cat_names.len);
    errdefer allocator.free(deltas);
    for (cat_names, fresh_vals, base_vals, 0..) |name, fv, bv, idx| {
        deltas[idx] = .{ .category = name, .before = bv, .after = fv };
    }

    // introduced = in fresh but not in baseline
    var introduced: std.ArrayList([]const u8) = .empty;
    errdefer { for (introduced.items) |s| allocator.free(s); introduced.deinit(allocator); }
    for (fresh.score_result.findings) |f| {
        var found = false;
        for (baseline.rule_ids) |rid| if (std.mem.eql(u8, f.rule_id, rid)) { found = true; break; };
        if (!found) try introduced.append(allocator, try allocator.dupe(u8, f.rule_id));
    }

    // resolved = in baseline but not in fresh
    var resolved: std.ArrayList([]const u8) = .empty;
    errdefer { for (resolved.items) |s| allocator.free(s); resolved.deinit(allocator); }
    for (baseline.rule_ids) |rid| {
        var found = false;
        for (fresh.score_result.findings) |f| if (std.mem.eql(u8, f.rule_id, rid)) { found = true; break; };
        if (!found) try resolved.append(allocator, try allocator.dupe(u8, rid));
    }

    return .{
        .url = fresh.url,
        .score_deltas = deltas,
        .introduced = try introduced.toOwnedSlice(allocator),
        .resolved = try resolved.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

// ── renderDiff ────────────────────────────────────────────────────────────────

pub fn renderDiff(result: DiffResult, out: *std.Io.Writer) !void {
    for (result.pages) |page| {
        try out.print("=== Diff: {s} ===\n", .{page.url});
        for (page.score_deltas) |d| {
            if (d.before == d.after) continue;
            const symbol: u8 = if (d.after > d.before) '+' else '-';
            const diff_val: u8 = if (d.after > d.before) d.after - d.before else d.before - d.after;
            const tag = if (d.regressed()) " [REGRESSION]" else "";
            try out.print("  {s:<18} {d} -> {d} ({c}{d}){s}\n", .{ d.category, d.before, d.after, symbol, diff_val, tag });
        }
        if (page.introduced.len > 0) {
            try out.print("  introduced ({d}):\n", .{page.introduced.len});
            for (page.introduced) |r| try out.print("    + {s}\n", .{r});
        }
        if (page.resolved.len > 0) {
            try out.print("  resolved ({d}):\n", .{page.resolved.len});
            for (page.resolved) |r| try out.print("    - {s}\n", .{r});
        }
    }
}

// ── tests ─────────────────────────────────────────────────────────────────────

test "ScoreDelta.regressed true when drop >= 5" {
    const d = ScoreDelta{ .category = "seo", .before = 90, .after = 80 };
    try std.testing.expect(d.regressed());
}

test "ScoreDelta.regressed false when drop < 5" {
    const d = ScoreDelta{ .category = "seo", .before = 90, .after = 87 };
    try std.testing.expect(!d.regressed());
}

test "ScoreDelta.regressed false when score improved" {
    const d = ScoreDelta{ .category = "seo", .before = 70, .after = 90 };
    try std.testing.expect(!d.regressed());
}

test "parseBaselinePage extracts url and scores" {
    const JSON =
        \\{"url":"https://example.com","status":200,"body_len":1000,"duration_ms":50,
        \\"profile":"desktop","gpu_accelerated":true,
        \\"title":"T","description":"D","h1":"H",
        \\"link_count":0,"internal_links":0,"external_links":0,"heading_count":0,
        \\"has_robots":false,"sitemap_url":null,
        \\"keyword_analysis":{"total_words":0,"top_keywords":[],"target_keyword":null},
        \\"keyword_coverages":[],
        \\"aeo_data":{"has_faq_schema":false,"has_howto_schema":false,"has_article_schema":false,
        \\"has_author_entity":false,"has_publisher_entity":false,"has_qa_headings":false,"outbound_link_count":0},
        \\"hreflang_count":0,
        \\"scores":{"performance":85,"accessibility":90,"best_practices":100,"seo":75,"gdpr":100,"keyword":95,"aeo":70},
        \\"findings":[{"rule_id":"seo_missing_canonical","category":"seo","severity":"info","detail":"no canonical link element"}]}
    ;
    const allocator = std.testing.allocator;
    const page = try parseBaselinePage(JSON, allocator);
    defer page.deinit();
    try std.testing.expectEqualStrings("https://example.com", page.url);
    try std.testing.expectEqual(@as(u8, 85), page.performance);
    try std.testing.expectEqual(@as(u8, 75), page.seo);
    try std.testing.expectEqual(@as(usize, 1), page.rule_ids.len);
    try std.testing.expectEqualStrings("seo_missing_canonical", page.rule_ids[0]);
}
