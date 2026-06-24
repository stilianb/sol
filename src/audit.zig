const std = @import("std");
const Io = std.Io;
const fetcher = @import("fetcher.zig");
const html_mod = @import("parser/html.zig");
const robots_mod = @import("crawler/robots.zig");
const sitemap_mod = @import("crawler/sitemap.zig");
const wcag_mod = @import("auditor/wcag.zig");
const perf_mod = @import("auditor/performance.zig");
const cookies_mod = @import("auditor/cookies.zig");
const seo_mod = @import("auditor/seo.zig");
const bp_mod = @import("auditor/best_practices.zig");
const keywords_mod = @import("auditor/keywords.zig");
const aeo_mod = @import("auditor/aeo.zig");
const scorer_mod = @import("auditor/scorer.zig");
const psi_mod = @import("psi/types.zig");
const helpers = @import("xml_helpers.zig");

// ── types ─────────────────────────────────────────────────────────────────────

pub const DeviceProfile = enum { desktop, tablet, mobile };

pub const AuditProfile = struct {
    profile: DeviceProfile,
    gpu_accelerated: bool,
};

pub const AuditReport = struct {
    url: []const u8,
    status: std.http.Status,
    body_len: usize,
    duration_ms: u64,
    title: ?[]const u8,
    description: ?[]const u8,
    h1: ?[]const u8,
    links: []const html_mod.Link,
    internal_link_count: usize,
    external_link_count: usize,
    headings: []const html_mod.Heading,
    wcag: wcag_mod.WcagData,
    performance: perf_mod.PerformanceData,
    cookies: cookies_mod.CookieData,
    seo: seo_mod.SeoData,
    best_practices: bp_mod.BestPracticesData,
    keywords: keywords_mod.KeywordData,
    keyword_coverages: []keywords_mod.KeywordCoverage,
    aeo: aeo_mod.AeoData,
    score_result: scorer_mod.ScoreResult,
    psi: ?psi_mod.PsiData,
    has_robots: bool,
    robots: robots_mod.Rules,
    sitemap_source: ?[]const u8,
    sitemap: ?sitemap_mod.ParseResult,
    audit_profile: AuditProfile,
    allocator: std.mem.Allocator,

    pub fn deinit(self: AuditReport) void {
        self.allocator.free(self.url);
        if (self.title) |t| self.allocator.free(t);
        if (self.description) |d| self.allocator.free(d);
        if (self.h1) |s| self.allocator.free(s);
        for (self.links) |l| self.allocator.free(l.href);
        self.allocator.free(self.links);
        for (self.headings) |hd| self.allocator.free(hd.text);
        self.allocator.free(self.headings);
        self.wcag.deinit();
        self.performance.deinit();
        self.cookies.deinit();
        self.seo.deinit();
        self.best_practices.deinit();
        self.keywords.deinit();
        for (self.keyword_coverages) |kc| kc.deinit();
        self.allocator.free(self.keyword_coverages);
        self.aeo.deinit();
        self.score_result.deinit();
        if (self.psi) |p| p.deinit();
        self.robots.deinit();
        if (self.sitemap_source) |s| self.allocator.free(s);
        if (self.sitemap) |sm| sm.deinit();
    }
};

// ── run ───────────────────────────────────────────────────────────────────────

pub fn run(url: []const u8, audit_profile: AuditProfile, goal_keywords: []const []const u8, io: Io, allocator: std.mem.Allocator) !AuditReport {
    const profile_name = @tagName(audit_profile.profile);
    // fetch page
    const page_fetch = try fetcher.fetchWith(io, allocator, url, .{ .profile_name = profile_name });
    defer allocator.free(page_fetch.body);

    // parse HTML
    const doc = html_mod.parse(page_fetch.body) orelse return error.ParseFailed;
    defer doc.deinit();

    // page-level data
    const title = doc.title(allocator);
    errdefer if (title) |t| allocator.free(t);
    const description = doc.metaDescription(allocator);
    errdefer if (description) |d| allocator.free(d);
    const h1 = doc.h1(allocator);
    errdefer if (h1) |s| allocator.free(s);

    const page_links = doc.classifiedLinks(url, allocator);
    errdefer { for (page_links) |l| allocator.free(l.href); allocator.free(page_links); }

    const page_headings = doc.headings(allocator);
    errdefer { for (page_headings) |hd| allocator.free(hd.text); allocator.free(page_headings); }

    var internal_count: usize = 0;
    var external_count: usize = 0;
    for (page_links) |l| if (l.is_internal) { internal_count += 1; } else { external_count += 1; };

    // auditors
    const wcag_data = try wcag_mod.extract(doc, allocator);
    errdefer wcag_data.deinit();

    const perf_data = try perf_mod.extract(doc, url, page_fetch.duration_ms, page_fetch.body.len, allocator);
    errdefer perf_data.deinit();

    const cookies_data = try cookies_mod.extract(doc, url, allocator);
    errdefer cookies_data.deinit();

    const seo_data = try seo_mod.extract(doc, allocator);
    errdefer seo_data.deinit();

    const bp_data = try bp_mod.extract(doc, url, page_fetch.redirect_depth, allocator);
    errdefer bp_data.deinit();

    const primary_kw: ?[]const u8 = if (goal_keywords.len > 0) goal_keywords[0] else null;
    const keywords_data = try keywords_mod.extract(doc, primary_kw, allocator);
    errdefer keywords_data.deinit();

    const keyword_coverages = try keywords_mod.checkKeywords(doc, goal_keywords, allocator);
    errdefer {
        for (keyword_coverages) |kc| kc.deinit();
        allocator.free(keyword_coverages);
    }

    const aeo_data = try aeo_mod.extract(doc, url, allocator);
    errdefer aeo_data.deinit();

    // robots.txt
    const origin = helpers.extractOrigin(url) orelse url;
    const robots_url = try std.mem.concat(allocator, u8, &.{ origin, "/robots.txt" });
    defer allocator.free(robots_url);

    const robots_fetch = fetcher.fetchWith(io, allocator, robots_url, .{ .profile_name = profile_name }) catch null;
    defer if (robots_fetch) |r| allocator.free(r.body);

    const robots_body = if (robots_fetch) |r| if (r.status == .ok) r.body else "" else "";
    const has_robots = robots_body.len > 0;

    const robots_rules = try robots_mod.parse(robots_body, "sol", allocator);
    errdefer robots_rules.deinit();

    // sitemap discovery
    const candidates = try sitemap_mod.candidateUrls(origin, robots_rules.sitemaps, allocator);
    defer { for (candidates) |u| allocator.free(u); allocator.free(candidates); }

    var sitemap_source: ?[]const u8 = null;
    var sitemap_result: ?sitemap_mod.ParseResult = null;
    errdefer if (sitemap_source) |s| allocator.free(s);
    errdefer if (sitemap_result) |sm| sm.deinit();

    for (candidates) |candidate| {
        const sm_fetch = fetcher.fetchWith(io, allocator, candidate, .{ .profile_name = profile_name }) catch continue;
        defer allocator.free(sm_fetch.body);
        if (sm_fetch.status != .ok) continue;
        const sm = sitemap_mod.parseSitemap(sm_fetch.body, allocator) catch continue;
        sitemap_source = try allocator.dupe(u8, candidate);
        sitemap_result = sm;
        break;
    }

    const has_sitemap = sitemap_result != null;
    const score_result = try scorer_mod.score(wcag_data, perf_data, cookies_data, seo_data, bp_data, keywords_data, aeo_data, has_sitemap, allocator);
    errdefer score_result.deinit();

    const url_owned = try allocator.dupe(u8, url);

    return .{
        .url = url_owned,
        .status = page_fetch.status,
        .body_len = page_fetch.body.len,
        .duration_ms = page_fetch.duration_ms,
        .title = title,
        .description = description,
        .h1 = h1,
        .links = page_links,
        .internal_link_count = internal_count,
        .external_link_count = external_count,
        .headings = page_headings,
        .wcag = wcag_data,
        .performance = perf_data,
        .cookies = cookies_data,
        .seo = seo_data,
        .best_practices = bp_data,
        .keywords = keywords_data,
        .keyword_coverages = keyword_coverages,
        .aeo = aeo_data,
        .score_result = score_result,
        .psi = null,
        .has_robots = has_robots,
        .robots = robots_rules,
        .sitemap_source = sitemap_source,
        .sitemap = sitemap_result,
        .audit_profile = audit_profile,
        .allocator = allocator,
    };
}

// ── CompareEntry + renderCompare ─────────────────────────────────────────────

pub const CompareEntry = struct {
    url: []const u8,
    scores: scorer_mod.Scores,
    findings: []const scorer_mod.Finding,
};

pub fn renderCompare(entries: []const CompareEntry, out: *Io.Writer) !void {
    if (entries.len == 0) return;

    const cat_names = [_][]const u8{ "performance", "accessibility", "best_practices", "seo", "gdpr", "keyword", "aeo" };
    const cats = [_]scorer_mod.Category{ .performance, .accessibility, .best_practices, .seo, .gdpr, .keyword, .aeo };

    try out.print("\n=== Competitive Comparison ===\n", .{});
    try out.print("{s:<18}", .{""});
    for (entries) |e| try out.print("  {s:>12}", .{truncateUrl(e.url, 12)});
    try out.print("\n", .{});

    for (cat_names, cats) |name, cat| {
        try out.print("{s:<18}", .{name});
        for (entries) |e| {
            const s = switch (cat) {
                .performance => e.scores.performance,
                .accessibility => e.scores.accessibility,
                .best_practices => e.scores.best_practices,
                .seo => e.scores.seo,
                .gdpr => e.scores.gdpr,
                .keyword => e.scores.keyword,
                .aeo => e.scores.aeo,
            };
            try out.print("  {d:>12}", .{s});
        }
        try out.print("\n", .{});
    }

    try out.print("{s:-<18}", .{""});
    for (entries) |_| try out.print("  {s:->12}", .{""});
    try out.print("\n", .{});

    try out.print("{s:<18}", .{"findings"});
    for (entries) |e| {
        var crit: usize = 0;
        var warn: usize = 0;
        for (e.findings) |f| switch (f.severity) {
            .critical => crit += 1,
            .warning => warn += 1,
            .info => {},
        };
        try out.print("  {d:>3}c {d:>3}w    ", .{ crit, warn });
    }
    try out.print("\n", .{});
}

fn truncateUrl(url: []const u8, max: usize) []const u8 {
    const stripped = if (std.mem.startsWith(u8, url, "https://")) url[8..] else if (std.mem.startsWith(u8, url, "http://")) url[7..] else url;
    if (stripped.len <= max) return stripped;
    return stripped[0..max];
}

// ── renderCsv ─────────────────────────────────────────────────────────────────

pub fn csvEscapeDetail(detail: []const u8, buf: []u8) []const u8 {
    var needs_quote = false;
    for (detail) |ch| {
        if (ch == ',' or ch == '"' or ch == '\n') { needs_quote = true; break; }
    }
    if (!needs_quote) return detail;
    var pos: usize = 0;
    buf[pos] = '"'; pos += 1;
    for (detail) |ch| {
        if (ch == '"') { buf[pos] = '"'; pos += 1; }
        buf[pos] = ch; pos += 1;
    }
    buf[pos] = '"'; pos += 1;
    return buf[0..pos];
}

pub fn renderCsv(reports: []const AuditReport, out: *Io.Writer) !void {
    try out.print("url,rule_id,category,severity,detail\n", .{});
    var esc_buf: [512]u8 = undefined;
    for (reports) |report| {
        for (report.score_result.findings) |f| {
            try out.print("{s},{s},{s},{s},{s}\n", .{
                report.url,
                f.rule_id,
                @tagName(f.category),
                @tagName(f.severity),
                csvEscapeDetail(f.detail, &esc_buf),
            });
        }
    }
}

// ── tests ─────────────────────────────────────────────────────────────────────

test "csvEscapeDetail plain string unchanged" {
    var buf: [64]u8 = undefined;
    const out = csvEscapeDetail("no commas here", &buf);
    try std.testing.expectEqualStrings("no commas here", out);
}

test "csvEscapeDetail wraps in quotes when comma present" {
    var buf: [64]u8 = undefined;
    const out = csvEscapeDetail("3 render-blocking script(s)", &buf);
    try std.testing.expectEqualStrings("\"3 render-blocking script(s)\"", out);
}

test "csvEscapeDetail escapes embedded quotes" {
    var buf: [64]u8 = undefined;
    const out = csvEscapeDetail("say \"hello\", world", &buf);
    try std.testing.expectEqualStrings("\"say \"\"hello\"\", world\"", out);
}

test "DeviceProfile mobile variant exists" {
    const p: DeviceProfile = .mobile;
    try std.testing.expectEqual(DeviceProfile.mobile, p);
}

test "DeviceProfile has desktop and tablet variants" {
    _ = DeviceProfile.desktop;
    _ = DeviceProfile.tablet;
}

test "AuditProfile mobile has gpu_accelerated false" {
    const p: AuditProfile = .{ .profile = .mobile, .gpu_accelerated = false };
    try std.testing.expect(!p.gpu_accelerated);
    try std.testing.expectEqual(DeviceProfile.mobile, p.profile);
}

test "AuditProfile desktop has gpu_accelerated true" {
    const p: AuditProfile = .{ .profile = .desktop, .gpu_accelerated = true };
    try std.testing.expect(p.gpu_accelerated);
}

test "CompareEntry holds url, scores, and findings" {
    const entry = CompareEntry{
        .url = "https://example.com",
        .scores = .{ .performance = 80, .accessibility = 90, .best_practices = 85, .seo = 75, .gdpr = 100, .keyword = 95, .aeo = 70 },
        .findings = &.{},
    };
    try std.testing.expectEqualStrings("https://example.com", entry.url);
    try std.testing.expectEqual(@as(u8, 80), entry.scores.performance);
}


// ── renderText ────────────────────────────────────────────────────────────────

pub fn renderText(report: AuditReport, out: *Io.Writer) !void {
    // page audit
    try out.print("=== Page Audit: {s} ===\n", .{report.url});
    try out.print("profile     = {s} (gpu={})\n", .{ @tagName(report.audit_profile.profile), report.audit_profile.gpu_accelerated });
    try out.print("status      = {d}\n", .{@intFromEnum(report.status)});
    try out.print("body_len    = {d}\n", .{report.body_len});
    try out.print("title       = {s}\n", .{report.title orelse "(none)"});
    try out.print("description = {s}\n", .{report.description orelse "(none)"});
    try out.print("h1          = {s}\n", .{report.h1 orelse "(none)"});
    try out.print("links       = {d} ({d} internal, {d} external)\n", .{
        report.links.len, report.internal_link_count, report.external_link_count,
    });
    try out.print("headings    = {d}\n", .{report.headings.len});
    for (report.headings) |hd| try out.print("  h{d}: {s}\n", .{ hd.level, hd.text });

    // WCAG
    const w = report.wcag;
    try out.print("\n=== WCAG 2.2 Data ===\n", .{});
    try out.print("html_lang               = {s}\n", .{w.html_lang orelse "(missing)"});
    try out.print("has_title               = {}\n", .{w.has_title});
    try out.print("viewport_meta           = {s}\n", .{w.viewport_meta orelse "(missing)"});
    try out.print("viewport_disables_zoom  = {}\n", .{w.viewport_disables_zoom});
    try out.print("has_skip_link           = {}\n", .{w.has_skip_link});
    try out.print("h1_count                = {d}\n", .{w.h1_count});
    try out.print("heading_sequence        = ", .{});
    for (w.heading_sequence) |lvl| try out.print("h{d} ", .{lvl});
    try out.print("\n", .{});
    try out.print("images_total            = {d}\n", .{w.images.len});
    try out.print("images_missing_alt      = {d}\n", .{w.images_missing_alt});
    try out.print("images_empty_alt        = {d}\n", .{w.images_empty_alt});
    try out.print("empty_links             = {d}\n", .{w.empty_links});
    try out.print("generic_links           = {d}\n", .{w.generic_links});
    try out.print("inputs_total            = {d}\n", .{w.inputs.len});
    try out.print("inputs_missing_label    = {d}\n", .{w.inputs_missing_label});
    try out.print("has_main_landmark       = {}\n", .{w.has_main_landmark});
    try out.print("has_nav_landmark        = {}\n", .{w.has_nav_landmark});
    try out.print("tabindex_positive       = {d}\n", .{w.tabindex_positive_count});

    // performance
    const p = report.performance;
    try out.print("\n=== Performance Data ===\n", .{});
    try out.print("fetch_duration_ms       = {d}\n", .{p.fetch_duration_ms});
    try out.print("html_bytes              = {d}\n", .{p.html_bytes});
    try out.print("external_scripts        = {d}\n", .{p.external_scripts});
    try out.print("render_blocking_scripts = {d}\n", .{p.render_blocking_scripts});
    try out.print("inline_scripts          = {d}\n", .{p.inline_scripts});
    try out.print("inline_script_bytes     = {d}\n", .{p.inline_script_bytes});
    try out.print("async_scripts           = {d}\n", .{p.async_scripts});
    try out.print("defer_scripts           = {d}\n", .{p.defer_scripts});
    try out.print("external_stylesheets    = {d}\n", .{p.external_stylesheets});
    try out.print("inline_styles           = {d}\n", .{p.inline_styles});
    try out.print("inline_style_bytes      = {d}\n", .{p.inline_style_bytes});
    try out.print("image_count             = {d}\n", .{p.image_count});
    try out.print("images_missing_dims     = {d}\n", .{p.images_missing_dimensions});
    try out.print("preload_count           = {d}\n", .{p.preload_count});
    try out.print("prefetch_count          = {d}\n", .{p.prefetch_count});
    try out.print("preconnect_count        = {d}\n", .{p.preconnect_count});
    try out.print("dns_prefetch_count      = {d}\n", .{p.dns_prefetch_count});
    try out.print("third_party_domains     = {d}\n", .{p.third_party_domains.len});
    for (p.third_party_domains) |d| try out.print("  {s}\n", .{d});

    // cookies / GDPR
    const ck = report.cookies;
    try out.print("\n=== Cookie / GDPR Data ===\n", .{});
    try out.print("has_consent_banner      = {}\n", .{ck.has_consent_banner});
    try out.print("consent_tool            = {s}\n", .{ck.consent_tool orelse "(none detected)"});
    try out.print("3p_script_domains       = {d}\n", .{ck.third_party_script_domains.len});
    for (ck.third_party_script_domains) |d| try out.print("  {s}\n", .{d});
    try out.print("3p_iframe_domains       = {d}\n", .{ck.third_party_iframe_domains.len});
    for (ck.third_party_iframe_domains) |d| try out.print("  {s}\n", .{d});
    try out.print("known_trackers          = {d}\n", .{ck.known_trackers.len});
    for (ck.known_trackers) |t| try out.print("  {s} ({s})\n", .{ t.domain, @tagName(t.category) });

    // SEO
    const seo = report.seo;
    try out.print("\n=== SEO Data ===\n", .{});
    try out.print("canonical         = {s}\n", .{seo.canonical orelse "(none)"});
    try out.print("has_noindex       = {}\n", .{seo.has_noindex});
    try out.print("has_nofollow      = {}\n", .{seo.has_nofollow});
    try out.print("og_title          = {s}\n", .{seo.og_title orelse "(none)"});
    try out.print("og_description    = {s}\n", .{seo.og_description orelse "(none)"});
    try out.print("og_image          = {s}\n", .{seo.og_image orelse "(none)"});
    try out.print("has_structured_data = {}\n", .{seo.has_structured_data});
    try out.print("title_length       = {d}\n", .{seo.title_length});
    try out.print("description_length = {d}\n", .{seo.description_length});
    try out.print("hreflang_count     = {d}\n", .{seo.hreflang_count});

    // best practices
    const bp = report.best_practices;
    try out.print("\n=== Best Practices ===\n", .{});
    try out.print("is_https            = {}\n", .{bp.is_https});
    try out.print("mixed_content       = {d}\n", .{bp.mixed_content_count});
    try out.print("deprecated_tags     = {d}\n", .{bp.deprecated_tag_count});
    try out.print("redirect_depth      = {d}\n", .{bp.redirect_chain_depth});

    // keyword analysis
    const kw = report.keywords;
    try out.print("\n=== Keyword Analysis ===\n", .{});
    try out.print("total_words    = {d}\n", .{kw.total_words});
    if (kw.top_keywords.len == 0) {
        try out.print("top_keywords   = (none)\n", .{});
    } else {
        try out.print("top_keywords   = ", .{});
        for (kw.top_keywords, 0..) |kf, i| {
            if (i > 0) try out.print(", ", .{});
            try out.print("{s} ({d})", .{ kf.word, kf.count });
        }
        try out.print("\n", .{});
    }
    if (kw.target_keyword) |tk| {
        try out.print("target         = \"{s}\"\n", .{tk});
        try out.print("  in_title     = {}\n", .{kw.target_in_title});
        try out.print("  in_h1        = {}\n", .{kw.target_in_h1});
        try out.print("  in_desc      = {}\n", .{kw.target_in_description});
        try out.print("  density      = {d}‰\n", .{kw.keyword_density});
    } else {
        try out.print("target         = (none — pass --keyword to score)\n", .{});
    }

    // goal keyword coverage
    if (report.keyword_coverages.len > 0) {
        try out.print("\n=== Goal Keyword Coverage ({d}) ===\n", .{report.keyword_coverages.len});
        for (report.keyword_coverages) |kc| {
            try out.print("keyword   = \"{s}\"\n", .{kc.keyword});
            try out.print("  title   = {}\n", .{kc.in_title});
            try out.print("  h1      = {}\n", .{kc.in_h1});
            try out.print("  desc    = {}\n", .{kc.in_description});
            try out.print("  density = {d}‰\n", .{kc.density_permille});
            try out.print("  score   = {d}/100\n", .{kc.coverage_score});
        }
    }

    // AEO / GEO
    const ae = report.aeo;
    try out.print("\n=== AEO / GEO Data ===\n", .{});
    try out.print("faq_schema     = {}\n", .{ae.has_faq_schema});
    try out.print("howto_schema   = {}\n", .{ae.has_howto_schema});
    try out.print("article_schema = {}\n", .{ae.has_article_schema});
    try out.print("author_entity  = {}\n", .{ae.has_author_entity});
    try out.print("publisher      = {}\n", .{ae.has_publisher_entity});
    try out.print("qa_headings    = {}\n", .{ae.has_qa_headings});
    try out.print("outbound_links = {d}\n", .{ae.outbound_link_count});

    // PSI (optional)
    if (report.psi) |psi| {
        try out.print("\n=== PageSpeed Insights ({s}) ===\n", .{psi.strategy});
        if (psi.lcp_ms) |v| try out.print("lcp             = {d}ms\n", .{v});
        if (psi.fcp_ms) |v| try out.print("fcp             = {d}ms\n", .{v});
        if (psi.cls_score) |v| try out.print("cls             = {d:.3}\n", .{v});
        if (psi.tbt_ms) |v| try out.print("tbt             = {d}ms\n", .{v});
        if (psi.speed_index_ms) |v| try out.print("speed_index     = {d}ms\n", .{v});
        if (psi.inp_ms) |v| try out.print("inp             = {d}ms\n", .{v});
        if (psi.lighthouse_performance) |v| try out.print("lh_performance  = {d}\n", .{v});
        if (psi.lighthouse_accessibility) |v| try out.print("lh_accessibility= {d}\n", .{v});
        if (psi.lighthouse_best_practices) |v| try out.print("lh_best_practices={d}\n", .{v});
        if (psi.lighthouse_seo) |v| try out.print("lh_seo          = {d}\n", .{v});
    }

    // scores
    const sc = report.score_result;
    try out.print("\n=== Scores ===\n", .{});
    try out.print("performance    = {d}\n", .{sc.scores.performance});
    try out.print("accessibility  = {d}\n", .{sc.scores.accessibility});
    try out.print("best_practices = {d}\n", .{sc.scores.best_practices});
    try out.print("seo            = {d}\n", .{sc.scores.seo});
    try out.print("gdpr           = {d}\n", .{sc.scores.gdpr});
    try out.print("keyword        = {d}\n", .{sc.scores.keyword});
    try out.print("aeo            = {d}\n", .{sc.scores.aeo});

    if (sc.findings.len > 0) {
        try out.print("\n=== Findings ({d}) ===\n", .{sc.findings.len});
        for (sc.findings) |f| {
            try out.print("[{s}] {s}: {s}\n", .{ @tagName(f.severity), f.rule_id, f.detail });
        }
    }

    // robots
    const rb = report.robots;
    try out.print("\n=== Robots.txt ===\n", .{});
    if (!report.has_robots) {
        try out.print("not found\n", .{});
    } else {
        try out.print("crawl_delay = {d}ms\n", .{rb.crawl_delay_ms});
        try out.print("sitemaps    = {d}\n", .{rb.sitemaps.len});
        for (rb.sitemaps) |s| try out.print("  {s}\n", .{s});
        try out.print("disallowed  = {d} rules\n", .{rb.disallowed.len});
    }

    // sitemap
    try out.print("\n=== Sitemap ===\n", .{});
    if (report.sitemap_source == null) {
        try out.print("NOT FOUND\n", .{});
    } else {
        try out.print("source = {s}\n", .{report.sitemap_source.?});
        if (report.sitemap) |sm| {
            if (sm.is_index) {
                try out.print("type   = index ({d} child sitemaps)\n", .{sm.child_sitemaps.len});
                for (sm.child_sitemaps) |cs| try out.print("  {s}\n", .{cs});
            } else {
                try out.print("type   = urlset\n", .{});
                try out.print("urls   = {d}\n", .{sm.entries.len});
                try out.print("missing lastmod    = {d}\n", .{sm.missing_lastmod_count});
                try out.print("missing priority   = {d}\n", .{sm.missing_priority_count});
                try out.print("missing changefreq = {d}\n", .{sm.missing_changefreq_count});
            }
        }
    }
}

// ── renderSummary ─────────────────────────────────────────────────────────────

pub fn renderSummary(report: AuditReport, out: *Io.Writer) !void {
    const cats = [_]scorer_mod.Category{ .performance, .accessibility, .best_practices, .seo, .gdpr, .keyword, .aeo };
    const names = [_][]const u8{ "performance", "accessibility", "best_practices", "seo", "gdpr", "keyword", "aeo" };
    const scores_arr = [_]u8{
        report.score_result.scores.performance,
        report.score_result.scores.accessibility,
        report.score_result.scores.best_practices,
        report.score_result.scores.seo,
        report.score_result.scores.gdpr,
        report.score_result.scores.keyword,
        report.score_result.scores.aeo,
    };

    try out.print("\n=== Summary ===\n", .{});
    try out.print("{s:<18} {s:>5}  {s:>8}  {s:>7}  {s:>4}\n", .{ "category", "score", "critical", "warning", "info" });
    try out.print("{s:-<18} {s:->5}  {s:->8}  {s:->7}  {s:->4}\n", .{ "", "", "", "", "" });

    var total_crit: usize = 0;
    var total_warn: usize = 0;
    var total_info: usize = 0;

    for (cats, names, scores_arr) |cat, name, cat_score| {
        var crit: usize = 0;
        var warn: usize = 0;
        var info: usize = 0;
        for (report.score_result.findings) |f| {
            if (f.category != cat) continue;
            switch (f.severity) {
                .critical => crit += 1,
                .warning => warn += 1,
                .info => info += 1,
            }
        }
        total_crit += crit;
        total_warn += warn;
        total_info += info;
        try out.print("{s:<18} {d:>5}  {d:>8}  {d:>7}  {d:>4}\n", .{ name, cat_score, crit, warn, info });
    }

    try out.print("{s:-<18} {s:->5}  {s:->8}  {s:->7}  {s:->4}\n", .{ "", "", "", "", "" });
    try out.print("{s:<18} {s:>5}  {d:>8}  {d:>7}  {d:>4}\n", .{ "TOTAL", "", total_crit, total_warn, total_info });
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

fn jsonOptStr(out: *Io.Writer, s: ?[]const u8) !void {
    if (s) |v| try jsonStr(out, v) else try out.print("null", .{});
}

pub fn renderJson(report: AuditReport, out: *Io.Writer) !void {
    try out.print("{{", .{});
    try out.print("\"url\":", .{});
    try jsonStr(out, report.url);
    try out.print(",\"status\":{d}", .{@intFromEnum(report.status)});
    try out.print(",\"body_len\":{d}", .{report.body_len});
    try out.print(",\"duration_ms\":{d}", .{report.duration_ms});
    try out.print(",\"profile\":\"{s}\"", .{@tagName(report.audit_profile.profile)});
    try out.print(",\"gpu_accelerated\":{}", .{report.audit_profile.gpu_accelerated});
    try out.print(",\"title\":", .{});
    try jsonOptStr(out, report.title);
    try out.print(",\"description\":", .{});
    try jsonOptStr(out, report.description);
    try out.print(",\"h1\":", .{});
    try jsonOptStr(out, report.h1);
    try out.print(",\"link_count\":{d}", .{report.links.len});
    try out.print(",\"internal_links\":{d}", .{report.internal_link_count});
    try out.print(",\"external_links\":{d}", .{report.external_link_count});
    try out.print(",\"heading_count\":{d}", .{report.headings.len});
    try out.print(",\"has_robots\":{}", .{report.has_robots});
    try out.print(",\"sitemap_url\":", .{});
    try jsonOptStr(out, report.sitemap_source);

    // keyword analysis
    const kw = report.keywords;
    try out.print(",\"keyword_analysis\":{{", .{});
    try out.print("\"total_words\":{d}", .{kw.total_words});
    try out.print(",\"top_keywords\":[", .{});
    for (kw.top_keywords, 0..) |kf, i| {
        if (i > 0) try out.print(",", .{});
        try out.print("{{\"word\":", .{});
        try jsonStr(out, kf.word);
        try out.print(",\"count\":{d}}}", .{kf.count});
    }
    try out.print("]", .{});
    if (kw.target_keyword) |tk| {
        try out.print(",\"target_keyword\":", .{});
        try jsonStr(out, tk);
        try out.print(",\"in_title\":{},\"in_h1\":{},\"in_description\":{},\"density_permille\":{d}", .{
            kw.target_in_title, kw.target_in_h1, kw.target_in_description, kw.keyword_density,
        });
    } else {
        try out.print(",\"target_keyword\":null", .{});
    }
    try out.print("}}", .{});

    // goal keyword coverages
    try out.print(",\"keyword_coverages\":[", .{});
    for (report.keyword_coverages, 0..) |kc, i| {
        if (i > 0) try out.print(",", .{});
        try out.print("{{\"keyword\":", .{});
        try jsonStr(out, kc.keyword);
        try out.print(",\"in_title\":{},\"in_h1\":{},\"in_description\":{},\"density_permille\":{d},\"coverage_score\":{d}}}", .{
            kc.in_title, kc.in_h1, kc.in_description, kc.density_permille, kc.coverage_score,
        });
    }
    try out.print("]", .{});

    // SEO extras
    const seo_d = report.seo;
    try out.print(",\"hreflang_count\":{d}", .{seo_d.hreflang_count});

    // PSI (optional)
    if (report.psi) |psi_data| {
        try out.print(",\"psi\":{{\"strategy\":\"{s}\"", .{psi_data.strategy});
        if (psi_data.lcp_ms) |v| try out.print(",\"lcp_ms\":{d}", .{v}) else try out.print(",\"lcp_ms\":null", .{});
        if (psi_data.fcp_ms) |v| try out.print(",\"fcp_ms\":{d}", .{v}) else try out.print(",\"fcp_ms\":null", .{});
        if (psi_data.cls_score) |v| try out.print(",\"cls_score\":{d:.4}", .{v}) else try out.print(",\"cls_score\":null", .{});
        if (psi_data.tbt_ms) |v| try out.print(",\"tbt_ms\":{d}", .{v}) else try out.print(",\"tbt_ms\":null", .{});
        if (psi_data.speed_index_ms) |v| try out.print(",\"speed_index_ms\":{d}", .{v}) else try out.print(",\"speed_index_ms\":null", .{});
        if (psi_data.inp_ms) |v| try out.print(",\"inp_ms\":{d}", .{v}) else try out.print(",\"inp_ms\":null", .{});
        if (psi_data.lighthouse_performance) |v| try out.print(",\"lighthouse_performance\":{d}", .{v}) else try out.print(",\"lighthouse_performance\":null", .{});
        if (psi_data.lighthouse_accessibility) |v| try out.print(",\"lighthouse_accessibility\":{d}", .{v}) else try out.print(",\"lighthouse_accessibility\":null", .{});
        if (psi_data.lighthouse_best_practices) |v| try out.print(",\"lighthouse_best_practices\":{d}", .{v}) else try out.print(",\"lighthouse_best_practices\":null", .{});
        if (psi_data.lighthouse_seo) |v| try out.print(",\"lighthouse_seo\":{d}", .{v}) else try out.print(",\"lighthouse_seo\":null", .{});
        try out.print("}}", .{});
    } else {
        try out.print(",\"psi\":null", .{});
    }

    // AEO / GEO
    const ae = report.aeo;
    try out.print(",\"aeo_data\":{{", .{});
    try out.print("\"has_faq_schema\":{}", .{ae.has_faq_schema});
    try out.print(",\"has_howto_schema\":{}", .{ae.has_howto_schema});
    try out.print(",\"has_article_schema\":{}", .{ae.has_article_schema});
    try out.print(",\"has_author_entity\":{}", .{ae.has_author_entity});
    try out.print(",\"has_publisher_entity\":{}", .{ae.has_publisher_entity});
    try out.print(",\"has_qa_headings\":{}", .{ae.has_qa_headings});
    try out.print(",\"outbound_link_count\":{d}", .{ae.outbound_link_count});
    try out.print("}}", .{});

    // scores
    const sc = report.score_result.scores;
    try out.print(",\"scores\":{{", .{});
    try out.print("\"performance\":{d}", .{sc.performance});
    try out.print(",\"accessibility\":{d}", .{sc.accessibility});
    try out.print(",\"best_practices\":{d}", .{sc.best_practices});
    try out.print(",\"seo\":{d}", .{sc.seo});
    try out.print(",\"gdpr\":{d}", .{sc.gdpr});
    try out.print(",\"keyword\":{d}", .{sc.keyword});
    try out.print(",\"aeo\":{d}", .{sc.aeo});
    try out.print("}}", .{});

    // findings
    try out.print(",\"findings\":[", .{});
    for (report.score_result.findings, 0..) |f, idx| {
        if (idx > 0) try out.print(",", .{});
        try out.print("{{", .{});
        try out.print("\"rule_id\":", .{});
        try jsonStr(out, f.rule_id);
        try out.print(",\"category\":\"{s}\"", .{@tagName(f.category)});
        try out.print(",\"severity\":\"{s}\"", .{@tagName(f.severity)});
        try out.print(",\"detail\":", .{});
        try jsonStr(out, f.detail);
        try out.print("}}", .{});
    }
    try out.print("]", .{});

    try out.print("}}\n", .{});
}
