const std = @import("std");
const Io = std.Io;
const fetcher = @import("fetcher.zig");
const html_mod = @import("parser/html.zig");
const robots_mod = @import("crawler/robots.zig");
const sitemap_mod = @import("crawler/sitemap.zig");
const wcag_mod = @import("auditor/wcag.zig");
const perf_mod = @import("auditor/performance.zig");
const cookies_mod = @import("auditor/cookies.zig");
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
        self.robots.deinit();
        if (self.sitemap_source) |s| self.allocator.free(s);
        if (self.sitemap) |sm| sm.deinit();
    }
};

// ── run ───────────────────────────────────────────────────────────────────────

pub fn run(url: []const u8, audit_profile: AuditProfile, io: Io, allocator: std.mem.Allocator) !AuditReport {
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
        .has_robots = has_robots,
        .robots = robots_rules,
        .sitemap_source = sitemap_source,
        .sitemap = sitemap_result,
        .audit_profile = audit_profile,
        .allocator = allocator,
    };
}

// ── tests ─────────────────────────────────────────────────────────────────────

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

test "run stores mobile profile in report" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const profile: AuditProfile = .{ .profile = .mobile, .gpu_accelerated = false };
    const report = try run("https://example.com", profile, io, allocator);
    defer report.deinit();
    try std.testing.expectEqual(DeviceProfile.mobile, report.audit_profile.profile);
    try std.testing.expect(!report.audit_profile.gpu_accelerated);
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
