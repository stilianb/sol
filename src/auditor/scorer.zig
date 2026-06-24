const std = @import("std");
const wcag_mod = @import("wcag.zig");
const perf_mod = @import("performance.zig");
const cookies_mod = @import("cookies.zig");
const seo_mod = @import("seo.zig");
const bp_mod = @import("best_practices.zig");
const keywords_mod = @import("keywords.zig");
const aeo_mod = @import("aeo.zig");

// ── types ─────────────────────────────────────────────────────────────────────

pub const Severity = enum { critical, warning, info };

pub const Category = enum { performance, accessibility, best_practices, seo, gdpr, keyword, aeo };

pub const Finding = struct {
    rule_id: []const u8,
    category: Category,
    severity: Severity,
    detail: []const u8,
};

pub const Scores = struct {
    performance: u8,
    accessibility: u8,
    best_practices: u8,
    seo: u8,
    gdpr: u8,
    keyword: u8,
    aeo: u8,
};

pub const ScoreResult = struct {
    findings: []Finding,
    scores: Scores,
    allocator: std.mem.Allocator,

    pub fn deinit(self: ScoreResult) void {
        for (self.findings) |f| self.allocator.free(f.detail);
        self.allocator.free(self.findings);
    }
};

// ── helpers ───────────────────────────────────────────────────────────────────

fn clampScore(penalty: i32) u8 {
    const result = 100 - penalty;
    if (result <= 0) return 0;
    if (result >= 100) return 100;
    return @intCast(result);
}

// ── score ─────────────────────────────────────────────────────────────────────

pub fn score(
    wcag: wcag_mod.WcagData,
    perf: perf_mod.PerformanceData,
    cookies: cookies_mod.CookieData,
    seo: seo_mod.SeoData,
    bp: bp_mod.BestPracticesData,
    keywords: keywords_mod.KeywordData,
    aeo: aeo_mod.AeoData,
    has_sitemap: bool,
    allocator: std.mem.Allocator,
) !ScoreResult {
    var findings: std.ArrayList(Finding) = .empty;
    errdefer {
        for (findings.items) |f| allocator.free(f.detail);
        findings.deinit(allocator);
    }

    var perf_pen: i32 = 0;
    var a11y_pen: i32 = 0;
    var bp_pen: i32 = 0;
    var seo_pen: i32 = 0;
    var gdpr_pen: i32 = 0;
    var kw_pen: i32 = 0;
    var aeo_pen: i32 = 0;

    // ── Performance ───────────────────────────────────────────────────────────

    if (perf.render_blocking_scripts > 0) {
        const n = perf.render_blocking_scripts;
        const sev: Severity = if (n >= 3) .critical else .warning;
        perf_pen += if (n >= 3) 25 else 10;
        try findings.append(allocator, .{
            .rule_id = "perf_render_blocking_scripts",
            .category = .performance,
            .severity = sev,
            .detail = try std.fmt.allocPrint(allocator, "{d} render-blocking script(s)", .{n}),
        });
    }

    if (perf.images_missing_dimensions > 0) {
        const n = perf.images_missing_dimensions;
        perf_pen += if (n >= 4) 15 else 5;
        try findings.append(allocator, .{
            .rule_id = "perf_missing_image_dims",
            .category = .performance,
            .severity = .warning,
            .detail = try std.fmt.allocPrint(allocator, "{d} image(s) missing width/height", .{n}),
        });
    }

    if (perf.inline_script_bytes > 5000) {
        const n = perf.inline_script_bytes;
        const sev: Severity = if (n > 20000) .warning else .info;
        perf_pen += if (n > 20000) 15 else 5;
        try findings.append(allocator, .{
            .rule_id = "perf_inline_script_bytes",
            .category = .performance,
            .severity = sev,
            .detail = try std.fmt.allocPrint(allocator, "{d} bytes of inline script", .{n}),
        });
    }

    if (perf.third_party_domains.len >= 3) {
        const n = perf.third_party_domains.len;
        const sev: Severity = if (n >= 6) .warning else .info;
        perf_pen += if (n >= 6) 15 else 5;
        try findings.append(allocator, .{
            .rule_id = "perf_third_party_count",
            .category = .performance,
            .severity = sev,
            .detail = try std.fmt.allocPrint(allocator, "{d} third-party domain(s)", .{n}),
        });
    }

    // ── Accessibility ─────────────────────────────────────────────────────────

    if (wcag.images_missing_alt > 0) {
        const n = wcag.images_missing_alt;
        a11y_pen += if (n >= 3) 25 else 10;
        try findings.append(allocator, .{
            .rule_id = "a11y_missing_image_alt",
            .category = .accessibility,
            .severity = .critical,
            .detail = try std.fmt.allocPrint(allocator, "{d} image(s) missing alt text", .{n}),
        });
    }

    if (wcag.inputs_missing_label > 0) {
        const n = wcag.inputs_missing_label;
        a11y_pen += if (n >= 3) 25 else 10;
        try findings.append(allocator, .{
            .rule_id = "a11y_missing_input_label",
            .category = .accessibility,
            .severity = .critical,
            .detail = try std.fmt.allocPrint(allocator, "{d} input(s) missing label", .{n}),
        });
    }

    if (wcag.tabindex_positive_count > 0) {
        const n = wcag.tabindex_positive_count;
        a11y_pen += if (n >= 3) 15 else 5;
        try findings.append(allocator, .{
            .rule_id = "a11y_positive_tabindex",
            .category = .accessibility,
            .severity = .warning,
            .detail = try std.fmt.allocPrint(allocator, "{d} element(s) with positive tabindex", .{n}),
        });
    }

    if (wcag.viewport_disables_zoom) {
        a11y_pen += 15;
        try findings.append(allocator, .{
            .rule_id = "a11y_viewport_zoom_disabled",
            .category = .accessibility,
            .severity = .critical,
            .detail = try allocator.dupe(u8, "viewport meta disables user zoom"),
        });
    }

    if (wcag.html_lang == null) {
        a11y_pen += 20;
        try findings.append(allocator, .{
            .rule_id = "a11y_missing_lang",
            .category = .accessibility,
            .severity = .critical,
            .detail = try allocator.dupe(u8, "html element missing lang attribute"),
        });
    }

    // ── Best practices ────────────────────────────────────────────────────────

    if (bp.mixed_content_count > 0) {
        const n = bp.mixed_content_count;
        bp_pen += if (n >= 3) 25 else 10;
        try findings.append(allocator, .{
            .rule_id = "bp_mixed_content",
            .category = .best_practices,
            .severity = .critical,
            .detail = try std.fmt.allocPrint(allocator, "{d} mixed-content resource(s)", .{n}),
        });
    }

    if (bp.deprecated_tag_count > 0) {
        const n = bp.deprecated_tag_count;
        bp_pen += if (n >= 3) 15 else 5;
        try findings.append(allocator, .{
            .rule_id = "bp_deprecated_elements",
            .category = .best_practices,
            .severity = .warning,
            .detail = try std.fmt.allocPrint(allocator, "{d} deprecated HTML element(s)", .{n}),
        });
    }

    if (!bp.is_https) {
        bp_pen += 30;
        try findings.append(allocator, .{
            .rule_id = "bp_missing_https",
            .category = .best_practices,
            .severity = .critical,
            .detail = try allocator.dupe(u8, "page served over HTTP"),
        });
    }

    // ── SEO ───────────────────────────────────────────────────────────────────

    if (seo.title_length == 0) {
        seo_pen += 20;
        try findings.append(allocator, .{
            .rule_id = "seo_missing_title",
            .category = .seo,
            .severity = .critical,
            .detail = try allocator.dupe(u8, "page has no title"),
        });
    } else if (seo.title_length < 10) {
        seo_pen += 10;
        try findings.append(allocator, .{
            .rule_id = "seo_title_too_short",
            .category = .seo,
            .severity = .warning,
            .detail = try std.fmt.allocPrint(allocator, "title is {d} chars; 10–60 recommended", .{seo.title_length}),
        });
    } else if (seo.title_length > 70) {
        seo_pen += 5;
        try findings.append(allocator, .{
            .rule_id = "seo_title_too_long",
            .category = .seo,
            .severity = .info,
            .detail = try std.fmt.allocPrint(allocator, "title is {d} chars; keep under 70", .{seo.title_length}),
        });
    }

    if (seo.description_length == 0) {
        seo_pen += 10;
        try findings.append(allocator, .{
            .rule_id = "seo_missing_description",
            .category = .seo,
            .severity = .warning,
            .detail = try allocator.dupe(u8, "page has no meta description"),
        });
    } else if (seo.description_length < 50) {
        seo_pen += 5;
        try findings.append(allocator, .{
            .rule_id = "seo_description_too_short",
            .category = .seo,
            .severity = .warning,
            .detail = try std.fmt.allocPrint(allocator, "description is {d} chars; 50–160 recommended", .{seo.description_length}),
        });
    } else if (seo.description_length > 160) {
        seo_pen += 5;
        try findings.append(allocator, .{
            .rule_id = "seo_description_too_long",
            .category = .seo,
            .severity = .info,
            .detail = try std.fmt.allocPrint(allocator, "description is {d} chars; keep under 160", .{seo.description_length}),
        });
    }

    if (seo.canonical == null) {
        seo_pen += 5;
        try findings.append(allocator, .{
            .rule_id = "seo_missing_canonical",
            .category = .seo,
            .severity = .info,
            .detail = try allocator.dupe(u8, "no canonical link element"),
        });
    }

    if (seo.has_noindex) {
        seo_pen += 30;
        try findings.append(allocator, .{
            .rule_id = "seo_noindex_present",
            .category = .seo,
            .severity = .critical,
            .detail = try allocator.dupe(u8, "page has noindex directive"),
        });
    }

    if (seo.og_title == null and seo.og_image == null) {
        seo_pen += 5;
        try findings.append(allocator, .{
            .rule_id = "seo_missing_og_tags",
            .category = .seo,
            .severity = .info,
            .detail = try allocator.dupe(u8, "og:title and og:image both absent"),
        });
    }

    if (!has_sitemap) {
        seo_pen += 5;
        try findings.append(allocator, .{
            .rule_id = "seo_missing_sitemap",
            .category = .seo,
            .severity = .info,
            .detail = try allocator.dupe(u8, "no sitemap found"),
        });
    }

    // ── GDPR ──────────────────────────────────────────────────────────────────

    if (cookies.known_trackers.len > 0 and !cookies.has_consent_banner) {
        const n = cookies.known_trackers.len;
        gdpr_pen += 30;
        try findings.append(allocator, .{
            .rule_id = "gdpr_no_consent_banner",
            .category = .gdpr,
            .severity = .critical,
            .detail = try std.fmt.allocPrint(allocator, "{d} tracker(s) present but no consent banner", .{n}),
        });
    }

    // ── Keyword ───────────────────────────────────────────────────────────────

    // content quality — always fire when we have extractable text
    if (keywords.total_words > 0) {
        if (keywords.top_keywords.len == 0) {
            kw_pen += 15;
            try findings.append(allocator, .{
                .rule_id = "kw_no_extractable_content",
                .category = .keyword,
                .severity = .warning,
                .detail = try allocator.dupe(u8, "no content words found after filtering stop words"),
            });
        } else if (keywords.total_words < 300) {
            kw_pen += 10;
            try findings.append(allocator, .{
                .rule_id = "kw_thin_content",
                .category = .keyword,
                .severity = .warning,
                .detail = try std.fmt.allocPrint(allocator, "page has {d} words; 300+ recommended for rankable content", .{keywords.total_words}),
            });
        }
    }

    if (keywords.target_keyword != null) {
        if (!keywords.target_in_title) {
            kw_pen += 15;
            try findings.append(allocator, .{
                .rule_id = "kw_target_missing_from_title",
                .category = .keyword,
                .severity = .critical,
                .detail = try allocator.dupe(u8, "target keyword not found in page title"),
            });
        }

        if (!keywords.target_in_h1) {
            kw_pen += 10;
            try findings.append(allocator, .{
                .rule_id = "kw_target_missing_from_h1",
                .category = .keyword,
                .severity = .warning,
                .detail = try allocator.dupe(u8, "target keyword not found in h1 heading"),
            });
        }

        if (!keywords.target_in_description) {
            kw_pen += 5;
            try findings.append(allocator, .{
                .rule_id = "kw_target_missing_from_description",
                .category = .keyword,
                .severity = .info,
                .detail = try allocator.dupe(u8, "target keyword not found in meta description"),
            });
        }

        if (keywords.keyword_density > 30) {
            kw_pen += 10;
            try findings.append(allocator, .{
                .rule_id = "kw_keyword_stuffing",
                .category = .keyword,
                .severity = .warning,
                .detail = try std.fmt.allocPrint(allocator, "keyword density {d}‰ exceeds 30‰ threshold", .{keywords.keyword_density}),
            });
        }

        if (keywords.total_words >= 100 and keywords.keyword_density < 5) {
            kw_pen += 5;
            try findings.append(allocator, .{
                .rule_id = "kw_low_keyword_density",
                .category = .keyword,
                .severity = .info,
                .detail = try std.fmt.allocPrint(allocator, "keyword density {d}‰ is below 5‰ minimum", .{keywords.keyword_density}),
            });
        }
    }

    // ── AEO ───────────────────────────────────────────────────────────────────

    if (!aeo.has_faq_schema and !aeo.has_howto_schema and !aeo.has_article_schema) {
        aeo_pen += 15;
        try findings.append(allocator, .{
            .rule_id = "aeo_no_structured_schema",
            .category = .aeo,
            .severity = .warning,
            .detail = try allocator.dupe(u8, "no FAQ, HowTo, or Article structured data found"),
        });
    }

    if (!aeo.has_author_entity and !aeo.has_publisher_entity) {
        aeo_pen += 10;
        try findings.append(allocator, .{
            .rule_id = "aeo_no_entity_signals",
            .category = .aeo,
            .severity = .warning,
            .detail = try allocator.dupe(u8, "no author or publisher entity signals found"),
        });
    }

    if (!aeo.has_qa_headings and !aeo.has_faq_schema) {
        aeo_pen += 10;
        try findings.append(allocator, .{
            .rule_id = "aeo_no_qa_content",
            .category = .aeo,
            .severity = .info,
            .detail = try allocator.dupe(u8, "no Q&A headings or FAQ schema detected"),
        });
    }

    if (aeo.outbound_link_count == 0) {
        aeo_pen += 5;
        try findings.append(allocator, .{
            .rule_id = "aeo_no_citations",
            .category = .aeo,
            .severity = .info,
            .detail = try allocator.dupe(u8, "no outbound citation links found"),
        });
    }

    return .{
        .findings = try findings.toOwnedSlice(allocator),
        .scores = .{
            .performance = clampScore(perf_pen),
            .accessibility = clampScore(a11y_pen),
            .best_practices = clampScore(bp_pen),
            .seo = clampScore(seo_pen),
            .gdpr = clampScore(gdpr_pen),
            .keyword = clampScore(kw_pen),
            .aeo = clampScore(aeo_pen),
        },
        .allocator = allocator,
    };
}

// ── test fixtures ─────────────────────────────────────────────────────────────

fn perfectWcag() wcag_mod.WcagData {
    return .{
        .html_lang = "en",
        .has_title = true,
        .viewport_meta = "width=device-width,initial-scale=1",
        .viewport_disables_zoom = false,
        .has_skip_link = true,
        .h1_count = 1,
        .heading_sequence = &.{},
        .images = &.{},
        .images_missing_alt = 0,
        .images_empty_alt = 0,
        .empty_links = 0,
        .generic_links = 0,
        .inputs = &.{},
        .inputs_missing_label = 0,
        .has_main_landmark = true,
        .has_nav_landmark = true,
        .tabindex_positive_count = 0,
        .allocator = std.testing.allocator,
    };
}

fn perfectPerf() perf_mod.PerformanceData {
    return .{
        .fetch_duration_ms = 50,
        .html_bytes = 2000,
        .external_scripts = 0,
        .render_blocking_scripts = 0,
        .inline_scripts = 0,
        .inline_script_bytes = 0,
        .async_scripts = 0,
        .defer_scripts = 0,
        .external_stylesheets = 0,
        .inline_styles = 0,
        .inline_style_bytes = 0,
        .image_count = 0,
        .images_missing_dimensions = 0,
        .preload_count = 0,
        .prefetch_count = 0,
        .preconnect_count = 0,
        .dns_prefetch_count = 0,
        .third_party_domains = &.{},
        .allocator = std.testing.allocator,
    };
}

fn perfectCookies() cookies_mod.CookieData {
    return .{
        .third_party_script_domains = &.{},
        .third_party_iframe_domains = &.{},
        .known_trackers = &.{},
        .has_consent_banner = false,
        .consent_tool = null,
        .allocator = std.testing.allocator,
    };
}

fn perfectSeo() seo_mod.SeoData {
    return .{
        .canonical = "https://example.com/",
        .has_noindex = false,
        .has_nofollow = false,
        .og_title = "Page Title",
        .og_description = null,
        .og_image = "https://example.com/img.png",
        .has_structured_data = false,
        .title_length = 20,
        .description_length = 80,
        .hreflang_count = 0,
        .allocator = std.testing.allocator,
    };
}

fn perfectBp() bp_mod.BestPracticesData {
    return .{
        .is_https = true,
        .mixed_content_count = 0,
        .deprecated_tag_count = 0,
        .redirect_chain_depth = 0,
        .allocator = std.testing.allocator,
    };
}

fn perfectKeywords() keywords_mod.KeywordData {
    return .{
        .top_keywords = &.{},
        .target_keyword = null,
        .target_in_title = false,
        .target_in_h1 = false,
        .target_in_description = false,
        .keyword_density = 0,
        .total_words = 0,
        .allocator = std.testing.allocator,
    };
}

fn perfectAeo() aeo_mod.AeoData {
    return .{
        .has_faq_schema = true,
        .has_howto_schema = false,
        .has_article_schema = false,
        .has_author_entity = true,
        .has_publisher_entity = false,
        .has_qa_headings = false,
        .outbound_link_count = 1,
        .allocator = std.testing.allocator,
    };
}

fn hasFinding(findings: []Finding, rule_id: []const u8) bool {
    for (findings) |f| if (std.mem.eql(u8, f.rule_id, rule_id)) return true;
    return false;
}

fn findSeverity(findings: []Finding, rule_id: []const u8) ?Severity {
    for (findings) |f| if (std.mem.eql(u8, f.rule_id, rule_id)) return f.severity;
    return null;
}

// ── tests ─────────────────────────────────────────────────────────────────────

test "Severity and Category enums have all variants" {
    _ = Severity.critical;
    _ = Severity.warning;
    _ = Severity.info;
    _ = Category.performance;
    _ = Category.accessibility;
    _ = Category.best_practices;
    _ = Category.seo;
    _ = Category.gdpr;
}

test "perfect mobile page scores 100 in all categories" {
    const allocator = std.testing.allocator;
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), perfectSeo(), perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 0), result.findings.len);
    try std.testing.expectEqual(@as(u8, 100), result.scores.performance);
    try std.testing.expectEqual(@as(u8, 100), result.scores.accessibility);
    try std.testing.expectEqual(@as(u8, 100), result.scores.best_practices);
    try std.testing.expectEqual(@as(u8, 100), result.scores.seo);
    try std.testing.expectEqual(@as(u8, 100), result.scores.gdpr);
}

test "perf_render_blocking_scripts warning for 1-2 scripts" {
    const allocator = std.testing.allocator;
    var p = perfectPerf();
    p.render_blocking_scripts = 2;
    const result = try score(perfectWcag(), p, perfectCookies(), perfectSeo(), perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "perf_render_blocking_scripts"));
    try std.testing.expectEqual(Severity.warning, findSeverity(result.findings, "perf_render_blocking_scripts").?);
    try std.testing.expectEqual(@as(u8, 90), result.scores.performance);
}

test "perf_render_blocking_scripts critical for 3+ scripts" {
    const allocator = std.testing.allocator;
    var p = perfectPerf();
    p.render_blocking_scripts = 3;
    const result = try score(perfectWcag(), p, perfectCookies(), perfectSeo(), perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expectEqual(Severity.critical, findSeverity(result.findings, "perf_render_blocking_scripts").?);
    try std.testing.expectEqual(@as(u8, 75), result.scores.performance);
}

test "perf_missing_image_dims fires for missing image dimensions" {
    const allocator = std.testing.allocator;
    var p = perfectPerf();
    p.images_missing_dimensions = 2;
    const result = try score(perfectWcag(), p, perfectCookies(), perfectSeo(), perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "perf_missing_image_dims"));
    try std.testing.expectEqual(@as(u8, 95), result.scores.performance);
}

test "perf_inline_script_bytes info for 5001-20000 bytes" {
    const allocator = std.testing.allocator;
    var p = perfectPerf();
    p.inline_script_bytes = 10000;
    const result = try score(perfectWcag(), p, perfectCookies(), perfectSeo(), perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "perf_inline_script_bytes"));
    try std.testing.expectEqual(Severity.info, findSeverity(result.findings, "perf_inline_script_bytes").?);
    try std.testing.expectEqual(@as(u8, 95), result.scores.performance);
}

test "perf_inline_script_bytes warning for 20001+ bytes" {
    const allocator = std.testing.allocator;
    var p = perfectPerf();
    p.inline_script_bytes = 21000;
    const result = try score(perfectWcag(), p, perfectCookies(), perfectSeo(), perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expectEqual(Severity.warning, findSeverity(result.findings, "perf_inline_script_bytes").?);
    try std.testing.expectEqual(@as(u8, 85), result.scores.performance);
}

test "perf_third_party_count fires for 3+ domains" {
    const allocator = std.testing.allocator;
    var p = perfectPerf();
    const domains = [_][]const u8{ "a.com", "b.com", "c.com" };
    p.third_party_domains = &domains;
    const result = try score(perfectWcag(), p, perfectCookies(), perfectSeo(), perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "perf_third_party_count"));
    try std.testing.expectEqual(@as(u8, 95), result.scores.performance);
}

test "a11y_missing_image_alt fires and penalizes score" {
    const allocator = std.testing.allocator;
    var w = perfectWcag();
    w.images_missing_alt = 1;
    const result = try score(w, perfectPerf(), perfectCookies(), perfectSeo(), perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "a11y_missing_image_alt"));
    try std.testing.expectEqual(Severity.critical, findSeverity(result.findings, "a11y_missing_image_alt").?);
    try std.testing.expectEqual(@as(u8, 90), result.scores.accessibility);
}

test "a11y_missing_input_label fires and penalizes score" {
    const allocator = std.testing.allocator;
    var w = perfectWcag();
    w.inputs_missing_label = 1;
    const result = try score(w, perfectPerf(), perfectCookies(), perfectSeo(), perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "a11y_missing_input_label"));
    try std.testing.expectEqual(@as(u8, 90), result.scores.accessibility);
}

test "a11y_positive_tabindex fires for positive tabindex" {
    const allocator = std.testing.allocator;
    var w = perfectWcag();
    w.tabindex_positive_count = 1;
    const result = try score(w, perfectPerf(), perfectCookies(), perfectSeo(), perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "a11y_positive_tabindex"));
    try std.testing.expectEqual(Severity.warning, findSeverity(result.findings, "a11y_positive_tabindex").?);
    try std.testing.expectEqual(@as(u8, 95), result.scores.accessibility);
}

test "a11y_viewport_zoom_disabled fires when zoom blocked" {
    const allocator = std.testing.allocator;
    var w = perfectWcag();
    w.viewport_disables_zoom = true;
    const result = try score(w, perfectPerf(), perfectCookies(), perfectSeo(), perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "a11y_viewport_zoom_disabled"));
    try std.testing.expectEqual(Severity.critical, findSeverity(result.findings, "a11y_viewport_zoom_disabled").?);
    try std.testing.expectEqual(@as(u8, 85), result.scores.accessibility);
}

test "a11y_missing_lang fires when html_lang is null" {
    const allocator = std.testing.allocator;
    var w = perfectWcag();
    w.html_lang = null;
    const result = try score(w, perfectPerf(), perfectCookies(), perfectSeo(), perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "a11y_missing_lang"));
    try std.testing.expectEqual(Severity.critical, findSeverity(result.findings, "a11y_missing_lang").?);
    try std.testing.expectEqual(@as(u8, 80), result.scores.accessibility);
}

test "bp_mixed_content fires for http resources on https page" {
    const allocator = std.testing.allocator;
    var bp = perfectBp();
    bp.mixed_content_count = 1;
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), perfectSeo(), bp, perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "bp_mixed_content"));
    try std.testing.expectEqual(Severity.critical, findSeverity(result.findings, "bp_mixed_content").?);
    try std.testing.expectEqual(@as(u8, 90), result.scores.best_practices);
}

test "bp_deprecated_elements fires for deprecated tags" {
    const allocator = std.testing.allocator;
    var bp = perfectBp();
    bp.deprecated_tag_count = 1;
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), perfectSeo(), bp, perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "bp_deprecated_elements"));
    try std.testing.expectEqual(Severity.warning, findSeverity(result.findings, "bp_deprecated_elements").?);
    try std.testing.expectEqual(@as(u8, 95), result.scores.best_practices);
}

test "bp_missing_https fires for http page" {
    const allocator = std.testing.allocator;
    var bp = perfectBp();
    bp.is_https = false;
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), perfectSeo(), bp, perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "bp_missing_https"));
    try std.testing.expectEqual(Severity.critical, findSeverity(result.findings, "bp_missing_https").?);
    try std.testing.expectEqual(@as(u8, 70), result.scores.best_practices);
}

test "seo_title_too_short fires warning when title under 10 chars (mobile fixture)" {
    const allocator = std.testing.allocator;
    var s = perfectSeo();
    s.title_length = 5;
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), s, perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "seo_title_too_short"));
    try std.testing.expectEqual(Severity.warning, findSeverity(result.findings, "seo_title_too_short").?);
}

test "seo_title_too_long fires info when title over 70 chars (mobile fixture)" {
    const allocator = std.testing.allocator;
    var s = perfectSeo();
    s.title_length = 80;
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), s, perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "seo_title_too_long"));
    try std.testing.expectEqual(Severity.info, findSeverity(result.findings, "seo_title_too_long").?);
}

test "no title length rule fires for optimal 20 char title (mobile fixture)" {
    const allocator = std.testing.allocator;
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), perfectSeo(), perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(!hasFinding(result.findings, "seo_title_too_short"));
    try std.testing.expect(!hasFinding(result.findings, "seo_title_too_long"));
}

test "seo_missing_og_tags fires info when og:title and og:image both absent (mobile fixture)" {
    const allocator = std.testing.allocator;
    var s = perfectSeo();
    s.og_title = null;
    s.og_image = null;
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), s, perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "seo_missing_og_tags"));
    try std.testing.expectEqual(Severity.info, findSeverity(result.findings, "seo_missing_og_tags").?);
}

test "seo_missing_og_tags does not fire when og:title present (mobile fixture)" {
    const allocator = std.testing.allocator;
    var s = perfectSeo();
    s.og_image = null;
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), s, perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(!hasFinding(result.findings, "seo_missing_og_tags"));
}

test "seo_missing_title fires when title_length is 0" {
    const allocator = std.testing.allocator;
    var s = perfectSeo();
    s.title_length = 0;
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), s, perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "seo_missing_title"));
    try std.testing.expectEqual(Severity.critical, findSeverity(result.findings, "seo_missing_title").?);
    try std.testing.expectEqual(@as(u8, 80), result.scores.seo);
}

test "seo_description_too_short fires warning under 50 chars (mobile fixture)" {
    const allocator = std.testing.allocator;
    var s = perfectSeo();
    s.description_length = 20;
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), s, perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "seo_description_too_short"));
    try std.testing.expectEqual(Severity.warning, findSeverity(result.findings, "seo_description_too_short").?);
}

test "seo_description_too_long fires info over 160 chars (mobile fixture)" {
    const allocator = std.testing.allocator;
    var s = perfectSeo();
    s.description_length = 200;
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), s, perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "seo_description_too_long"));
    try std.testing.expectEqual(Severity.info, findSeverity(result.findings, "seo_description_too_long").?);
}

test "no description length rule fires for optimal 80 char description (mobile fixture)" {
    const allocator = std.testing.allocator;
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), perfectSeo(), perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(!hasFinding(result.findings, "seo_description_too_short"));
    try std.testing.expect(!hasFinding(result.findings, "seo_description_too_long"));
}

test "seo_missing_description fires when description_length is 0" {
    const allocator = std.testing.allocator;
    var s = perfectSeo();
    s.description_length = 0;
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), s, perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "seo_missing_description"));
    try std.testing.expectEqual(Severity.warning, findSeverity(result.findings, "seo_missing_description").?);
    try std.testing.expectEqual(@as(u8, 90), result.scores.seo);
}

test "seo_missing_canonical fires when canonical is null" {
    const allocator = std.testing.allocator;
    var s = perfectSeo();
    s.canonical = null;
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), s, perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "seo_missing_canonical"));
    try std.testing.expectEqual(Severity.info, findSeverity(result.findings, "seo_missing_canonical").?);
    try std.testing.expectEqual(@as(u8, 95), result.scores.seo);
}

test "seo_noindex_present fires when has_noindex is true" {
    const allocator = std.testing.allocator;
    var s = perfectSeo();
    s.has_noindex = true;
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), s, perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "seo_noindex_present"));
    try std.testing.expectEqual(Severity.critical, findSeverity(result.findings, "seo_noindex_present").?);
    try std.testing.expectEqual(@as(u8, 70), result.scores.seo);
}

test "seo_missing_sitemap fires when has_sitemap is false" {
    const allocator = std.testing.allocator;
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), perfectSeo(), perfectBp(), perfectKeywords(), perfectAeo(), false, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "seo_missing_sitemap"));
    try std.testing.expectEqual(Severity.info, findSeverity(result.findings, "seo_missing_sitemap").?);
    try std.testing.expectEqual(@as(u8, 95), result.scores.seo);
}

test "gdpr_no_consent_banner fires when trackers present without banner" {
    const allocator = std.testing.allocator;
    const trackers = [_]cookies_mod.TrackerInfo{
        .{ .domain = "google-analytics.com", .category = .analytics },
    };
    const ck = cookies_mod.CookieData{
        .third_party_script_domains = &.{},
        .third_party_iframe_domains = &.{},
        .known_trackers = &trackers,
        .has_consent_banner = false,
        .consent_tool = null,
        .allocator = allocator,
    };
    const result = try score(perfectWcag(), perfectPerf(), ck, perfectSeo(), perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "gdpr_no_consent_banner"));
    try std.testing.expectEqual(Severity.critical, findSeverity(result.findings, "gdpr_no_consent_banner").?);
    try std.testing.expectEqual(@as(u8, 70), result.scores.gdpr);
}

test "gdpr_no_consent_banner does not fire when consent banner present" {
    const allocator = std.testing.allocator;
    const trackers = [_]cookies_mod.TrackerInfo{
        .{ .domain = "google-analytics.com", .category = .analytics },
    };
    const ck = cookies_mod.CookieData{
        .third_party_script_domains = &.{},
        .third_party_iframe_domains = &.{},
        .known_trackers = &trackers,
        .has_consent_banner = true,
        .consent_tool = null,
        .allocator = allocator,
    };
    const result = try score(perfectWcag(), perfectPerf(), ck, perfectSeo(), perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(!hasFinding(result.findings, "gdpr_no_consent_banner"));
    try std.testing.expectEqual(@as(u8, 100), result.scores.gdpr);
}

test "scores floor at 0 when penalties exceed 100" {
    const allocator = std.testing.allocator;
    var w = perfectWcag();
    w.html_lang = null; // -20
    w.viewport_disables_zoom = true; // -15
    w.images_missing_alt = 5; // -25
    w.inputs_missing_label = 5; // -25
    w.tabindex_positive_count = 5; // -15
    // total a11y penalty = 100 → score = 0
    const result = try score(w, perfectPerf(), perfectCookies(), perfectSeo(), perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.scores.accessibility);
}

test "kw_target_missing_from_title fires as critical when target not in title" {
    const allocator = std.testing.allocator;
    var kw = perfectKeywords();
    kw.target_keyword = "sol audit";
    kw.target_in_title = false;
    kw.target_in_h1 = true;
    kw.target_in_description = true;
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), perfectSeo(), perfectBp(), kw, perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "kw_target_missing_from_title"));
    try std.testing.expectEqual(Severity.critical, findSeverity(result.findings, "kw_target_missing_from_title").?);
    try std.testing.expectEqual(@as(u8, 85), result.scores.keyword);
}

test "kw_target_missing_from_h1 fires as warning when target not in h1" {
    const allocator = std.testing.allocator;
    var kw = perfectKeywords();
    kw.target_keyword = "sol audit";
    kw.target_in_title = true;
    kw.target_in_h1 = false;
    kw.target_in_description = true;
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), perfectSeo(), perfectBp(), kw, perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "kw_target_missing_from_h1"));
    try std.testing.expectEqual(Severity.warning, findSeverity(result.findings, "kw_target_missing_from_h1").?);
    try std.testing.expectEqual(@as(u8, 90), result.scores.keyword);
}

test "kw_target_missing_from_description fires as info when target not in description" {
    const allocator = std.testing.allocator;
    var kw = perfectKeywords();
    kw.target_keyword = "sol audit";
    kw.target_in_title = true;
    kw.target_in_h1 = true;
    kw.target_in_description = false;
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), perfectSeo(), perfectBp(), kw, perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "kw_target_missing_from_description"));
    try std.testing.expectEqual(Severity.info, findSeverity(result.findings, "kw_target_missing_from_description").?);
    try std.testing.expectEqual(@as(u8, 95), result.scores.keyword);
}

test "kw_keyword_stuffing fires when density exceeds 30 per-mille" {
    const allocator = std.testing.allocator;
    var kw = perfectKeywords();
    kw.target_keyword = "sol";
    kw.target_in_title = true;
    kw.target_in_h1 = true;
    kw.target_in_description = true;
    kw.keyword_density = 50;
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), perfectSeo(), perfectBp(), kw, perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "kw_keyword_stuffing"));
    try std.testing.expectEqual(Severity.warning, findSeverity(result.findings, "kw_keyword_stuffing").?);
    try std.testing.expectEqual(@as(u8, 90), result.scores.keyword);
}

test "kw_low_keyword_density fires when density below 5 per-mille on long page" {
    const allocator = std.testing.allocator;
    var fake_kws = [1]keywords_mod.KeywordFreq{.{ .word = "sol", .count = 5 }};
    var kw = perfectKeywords();
    kw.target_keyword = "sol";
    kw.target_in_title = true;
    kw.target_in_h1 = true;
    kw.target_in_description = true;
    kw.keyword_density = 2;
    kw.total_words = 400;
    kw.top_keywords = &fake_kws;
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), perfectSeo(), perfectBp(), kw, perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "kw_low_keyword_density"));
    try std.testing.expectEqual(@as(u8, 95), result.scores.keyword);
}

test "no keyword rules fire when no target keyword given" {
    const allocator = std.testing.allocator;
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), perfectSeo(), perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(!hasFinding(result.findings, "kw_target_missing_from_title"));
    try std.testing.expect(!hasFinding(result.findings, "kw_keyword_stuffing"));
    try std.testing.expectEqual(@as(u8, 100), result.scores.keyword);
}

test "aeo_no_structured_schema fires when no schema types present" {
    const allocator = std.testing.allocator;
    var a = perfectAeo();
    a.has_faq_schema = false;
    a.has_howto_schema = false;
    a.has_article_schema = false;
    a.has_qa_headings = true; // avoid triggering aeo_no_qa_content simultaneously
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), perfectSeo(), perfectBp(), perfectKeywords(), a, true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "aeo_no_structured_schema"));
    try std.testing.expectEqual(Severity.warning, findSeverity(result.findings, "aeo_no_structured_schema").?);
    try std.testing.expectEqual(@as(u8, 85), result.scores.aeo);
}

test "aeo_no_entity_signals fires when no author and no publisher" {
    const allocator = std.testing.allocator;
    var a = perfectAeo();
    a.has_author_entity = false;
    a.has_publisher_entity = false;
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), perfectSeo(), perfectBp(), perfectKeywords(), a, true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "aeo_no_entity_signals"));
    try std.testing.expectEqual(Severity.warning, findSeverity(result.findings, "aeo_no_entity_signals").?);
    try std.testing.expectEqual(@as(u8, 90), result.scores.aeo);
}

test "aeo_no_qa_content fires when no Q&A headings and no FAQ schema" {
    const allocator = std.testing.allocator;
    var a = perfectAeo();
    a.has_qa_headings = false;
    a.has_faq_schema = false;
    a.has_article_schema = true; // satisfy structured schema rule to isolate qa_content rule
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), perfectSeo(), perfectBp(), perfectKeywords(), a, true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "aeo_no_qa_content"));
    try std.testing.expectEqual(@as(u8, 90), result.scores.aeo);
}

test "aeo_no_citations fires when no outbound links" {
    const allocator = std.testing.allocator;
    var a = perfectAeo();
    a.outbound_link_count = 0;
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), perfectSeo(), perfectBp(), perfectKeywords(), a, true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "aeo_no_citations"));
    try std.testing.expectEqual(@as(u8, 95), result.scores.aeo);
}

test "perfect page scores 100 in keyword and aeo categories" {
    const allocator = std.testing.allocator;
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), perfectSeo(), perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 100), result.scores.keyword);
    try std.testing.expectEqual(@as(u8, 100), result.scores.aeo);
}

test "kw_thin_content fires for sparse page content" {
    const allocator = std.testing.allocator;
    var fake_kws = [1]keywords_mod.KeywordFreq{.{ .word = "content", .count = 3 }};
    var kw = perfectKeywords();
    kw.total_words = 50;
    kw.top_keywords = &fake_kws;
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), perfectSeo(), perfectBp(), kw, perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "kw_thin_content"));
    try std.testing.expect(result.scores.keyword < 100);
}

test "kw_no_extractable_content fires when all words are stop words" {
    const allocator = std.testing.allocator;
    var kw = perfectKeywords();
    kw.total_words = 200;
    kw.top_keywords = &.{};
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), perfectSeo(), perfectBp(), kw, perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(hasFinding(result.findings, "kw_no_extractable_content"));
    try std.testing.expect(result.scores.keyword < 100);
}

test "keyword score is 100 for adequate content without target keyword" {
    const allocator = std.testing.allocator;
    var fake_kws = [1]keywords_mod.KeywordFreq{.{ .word = "site", .count = 8 }};
    var kw = perfectKeywords();
    kw.total_words = 500;
    kw.top_keywords = &fake_kws;
    const result = try score(perfectWcag(), perfectPerf(), perfectCookies(), perfectSeo(), perfectBp(), kw, perfectAeo(), true, allocator);
    defer result.deinit();
    try std.testing.expect(!hasFinding(result.findings, "kw_thin_content"));
    try std.testing.expect(!hasFinding(result.findings, "kw_no_extractable_content"));
    try std.testing.expectEqual(@as(u8, 100), result.scores.keyword);
}

test "score is not affected by fetch timing (reproducibility guarantee)" {
    const allocator = std.testing.allocator;
    var p1 = perfectPerf();
    p1.fetch_duration_ms = 50;
    var p2 = perfectPerf();
    p2.fetch_duration_ms = 9000;
    const r1 = try score(perfectWcag(), p1, perfectCookies(), perfectSeo(), perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer r1.deinit();
    const r2 = try score(perfectWcag(), p2, perfectCookies(), perfectSeo(), perfectBp(), perfectKeywords(), perfectAeo(), true, allocator);
    defer r2.deinit();
    try std.testing.expectEqual(r1.scores.performance, r2.scores.performance);
    try std.testing.expectEqual(r1.scores.accessibility, r2.scores.accessibility);
    try std.testing.expectEqual(r1.scores.seo, r2.scores.seo);
    try std.testing.expectEqual(r1.scores.keyword, r2.scores.keyword);
    try std.testing.expectEqual(r1.scores.aeo, r2.scores.aeo);
}
