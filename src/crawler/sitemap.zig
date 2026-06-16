const std = @import("std");
const c = @import("../xml.zig").c;
const h = @import("../xml_helpers.zig");

// ── types ─────────────────────────────────────────────────────────────────────

pub const Entry = struct {
    loc: []const u8,
    lastmod: ?[]const u8,
    changefreq: ?[]const u8,
    priority: ?f32,
};

pub const ParseResult = struct {
    entries: []const Entry,
    is_index: bool,
    child_sitemaps: []const []const u8,
    missing_lastmod_count: usize,
    missing_priority_count: usize,
    missing_changefreq_count: usize,
    allocator: std.mem.Allocator,

    pub fn deinit(self: ParseResult) void {
        for (self.entries) |e| {
            self.allocator.free(e.loc);
            if (e.lastmod) |s| self.allocator.free(s);
            if (e.changefreq) |s| self.allocator.free(s);
        }
        self.allocator.free(self.entries);
        for (self.child_sitemaps) |s| self.allocator.free(s);
        self.allocator.free(self.child_sitemaps);
    }
};

pub const DiscoverySource = enum { robots_txt, common_path };

// ── helpers ───────────────────────────────────────────────────────────────────

fn childText(parent: *c.xmlNode, tag: []const u8, allocator: std.mem.Allocator) ?[]const u8 {
    var child = parent.*.children;
    while (child != null) : (child = child.*.next) {
        if (child.*.type != c.XML_ELEMENT_NODE) continue;
        if (std.mem.eql(u8, h.nodeLocalName(child.?), tag))
            return h.nodeText(child.?, allocator);
    }
    return null;
}

// ── implementation ────────────────────────────────────────────────────────────

pub fn parseSitemap(xml: []const u8, allocator: std.mem.Allocator) !ParseResult {
    if (xml.len == 0) return .{
        .entries = try allocator.alloc(Entry, 0),
        .is_index = false,
        .child_sitemaps = try allocator.alloc([]const u8, 0),
        .missing_lastmod_count = 0,
        .missing_priority_count = 0,
        .missing_changefreq_count = 0,
        .allocator = allocator,
    };

    c.xmlInitParser();
    const doc = c.xmlReadMemory(
        xml.ptr,
        @intCast(xml.len),
        null,
        null,
        0,
    ) orelse return .{
        .entries = try allocator.alloc(Entry, 0),
        .is_index = false,
        .child_sitemaps = try allocator.alloc([]const u8, 0),
        .missing_lastmod_count = 0,
        .missing_priority_count = 0,
        .missing_changefreq_count = 0,
        .allocator = allocator,
    };
    defer c.xmlFreeDoc(doc);

    const ctx = c.xmlXPathNewContext(doc) orelse return error.OutOfMemory;
    defer c.xmlXPathFreeContext(ctx);

    // detect sitemapindex vs urlset
    const index_obj = c.xmlXPathEvalExpression("//*[local-name()='sitemapindex']", ctx);
    defer if (index_obj != null) c.xmlXPathFreeObject(index_obj);
    const is_index = index_obj != null and
        index_obj.?.*.nodesetval != null and
        index_obj.?.*.nodesetval.?.*.nodeNr > 0;

    if (is_index) {
        const obj = c.xmlXPathEvalExpression("//*[local-name()='sitemap']", ctx) orelse
            return error.OutOfMemory;
        defer c.xmlXPathFreeObject(obj);

        const nodes = obj.*.nodesetval orelse return .{
            .entries = try allocator.alloc(Entry, 0),
            .is_index = true,
            .child_sitemaps = try allocator.alloc([]const u8, 0),
            .missing_lastmod_count = 0,
            .missing_priority_count = 0,
            .missing_changefreq_count = 0,
            .allocator = allocator,
        };

        var children: std.ArrayList([]const u8) = .empty;
        const count: usize = @intCast(nodes.*.nodeNr);
        for (0..count) |i| {
            const node = nodes.*.nodeTab[i] orelse continue;
            const loc = childText(node, "loc", allocator) orelse continue;
            try children.append(allocator, loc);
        }

        return .{
            .entries = try allocator.alloc(Entry, 0),
            .is_index = true,
            .child_sitemaps = try children.toOwnedSlice(allocator),
            .missing_lastmod_count = 0,
            .missing_priority_count = 0,
            .missing_changefreq_count = 0,
            .allocator = allocator,
        };
    }

    // flat urlset
    const obj = c.xmlXPathEvalExpression("//*[local-name()='url']", ctx) orelse
        return error.OutOfMemory;
    defer c.xmlXPathFreeObject(obj);

    const nodes = obj.*.nodesetval orelse return .{
        .entries = try allocator.alloc(Entry, 0),
        .is_index = false,
        .child_sitemaps = try allocator.alloc([]const u8, 0),
        .missing_lastmod_count = 0,
        .missing_priority_count = 0,
        .missing_changefreq_count = 0,
        .allocator = allocator,
    };

    var entries: std.ArrayList(Entry) = .empty;
    var missing_lastmod: usize = 0;
    var missing_priority: usize = 0;
    var missing_changefreq: usize = 0;

    const count: usize = @intCast(nodes.*.nodeNr);
    for (0..count) |i| {
        const node = nodes.*.nodeTab[i] orelse continue;
        const loc = childText(node, "loc", allocator) orelse continue;
        const lastmod = childText(node, "lastmod", allocator);
        const changefreq = childText(node, "changefreq", allocator);
        const priority_str = childText(node, "priority", allocator);
        defer if (priority_str) |s| allocator.free(s);

        const priority: ?f32 = if (priority_str) |s|
            std.fmt.parseFloat(f32, s) catch null
        else
            null;

        if (lastmod == null) missing_lastmod += 1;
        if (priority == null) missing_priority += 1;
        if (changefreq == null) missing_changefreq += 1;

        try entries.append(allocator, .{
            .loc = loc,
            .lastmod = lastmod,
            .changefreq = changefreq,
            .priority = priority,
        });
    }

    return .{
        .entries = try entries.toOwnedSlice(allocator),
        .is_index = false,
        .child_sitemaps = try allocator.alloc([]const u8, 0),
        .missing_lastmod_count = missing_lastmod,
        .missing_priority_count = missing_priority,
        .missing_changefreq_count = missing_changefreq,
        .allocator = allocator,
    };
}

const COMMON_PATHS = [_][]const u8{
    "/sitemap.xml",
    "/sitemap_index.xml",
    "/sitemap.xml.gz",
};

pub fn candidateUrls(
    base_url: []const u8,
    robots_sitemaps: []const []const u8,
    allocator: std.mem.Allocator,
) ![]const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;

    // robots.txt sitemaps first
    for (robots_sitemaps) |s|
        try list.append(allocator, try allocator.dupe(u8, s));

    // strip trailing slash from base_url
    const base = std.mem.trimEnd(u8, base_url, "/");

    for (COMMON_PATHS) |path| {
        const url = try std.mem.concat(allocator, u8, &.{ base, path });
        try list.append(allocator, url);
    }

    return list.toOwnedSlice(allocator);
}

// ── tests ─────────────────────────────────────────────────────────────────────

const FLAT_SITEMAP =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    \\  <url>
    \\    <loc>https://example.com/</loc>
    \\    <lastmod>2024-01-01</lastmod>
    \\    <changefreq>weekly</changefreq>
    \\    <priority>1.0</priority>
    \\  </url>
    \\  <url>
    \\    <loc>https://example.com/about</loc>
    \\    <lastmod>2024-02-01</lastmod>
    \\    <changefreq>monthly</changefreq>
    \\    <priority>0.8</priority>
    \\  </url>
    \\  <url>
    \\    <loc>https://example.com/blog</loc>
    \\  </url>
    \\</urlset>
;

const INDEX_SITEMAP =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    \\  <sitemap>
    \\    <loc>https://example.com/sitemap-pages.xml</loc>
    \\  </sitemap>
    \\  <sitemap>
    \\    <loc>https://example.com/sitemap-posts.xml</loc>
    \\  </sitemap>
    \\</sitemapindex>
;

test "parseSitemap: flat urlset returns correct entry count" {
    const result = try parseSitemap(FLAT_SITEMAP, std.testing.allocator);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 3), result.entries.len);
    try std.testing.expect(!result.is_index);
}

test "parseSitemap: extracts loc URLs" {
    const result = try parseSitemap(FLAT_SITEMAP, std.testing.allocator);
    defer result.deinit();

    try std.testing.expectEqualStrings("https://example.com/", result.entries[0].loc);
    try std.testing.expectEqualStrings("https://example.com/about", result.entries[1].loc);
    try std.testing.expectEqualStrings("https://example.com/blog", result.entries[2].loc);
}

test "parseSitemap: extracts optional fields" {
    const result = try parseSitemap(FLAT_SITEMAP, std.testing.allocator);
    defer result.deinit();

    const first = result.entries[0];
    try std.testing.expectEqualStrings("2024-01-01", first.lastmod orelse return error.Missing);
    try std.testing.expectEqualStrings("weekly", first.changefreq orelse return error.Missing);
    try std.testing.expectEqual(@as(f32, 1.0), first.priority orelse return error.Missing);
}

test "parseSitemap: null optional fields when absent" {
    const result = try parseSitemap(FLAT_SITEMAP, std.testing.allocator);
    defer result.deinit();

    const third = result.entries[2];
    try std.testing.expect(third.lastmod == null);
    try std.testing.expect(third.changefreq == null);
    try std.testing.expect(third.priority == null);
}

test "parseSitemap: counts missing optional fields" {
    const result = try parseSitemap(FLAT_SITEMAP, std.testing.allocator);
    defer result.deinit();

    // third entry missing lastmod, priority, changefreq
    try std.testing.expectEqual(@as(usize, 1), result.missing_lastmod_count);
    try std.testing.expectEqual(@as(usize, 1), result.missing_priority_count);
    try std.testing.expectEqual(@as(usize, 1), result.missing_changefreq_count);
}

test "parseSitemap: detects sitemapindex format" {
    const result = try parseSitemap(INDEX_SITEMAP, std.testing.allocator);
    defer result.deinit();

    try std.testing.expect(result.is_index);
    try std.testing.expectEqual(@as(usize, 0), result.entries.len);
    try std.testing.expectEqual(@as(usize, 2), result.child_sitemaps.len);
    try std.testing.expectEqualStrings("https://example.com/sitemap-pages.xml", result.child_sitemaps[0]);
    try std.testing.expectEqualStrings("https://example.com/sitemap-posts.xml", result.child_sitemaps[1]);
}

test "parseSitemap: empty xml returns empty result" {
    const result = try parseSitemap("", std.testing.allocator);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 0), result.entries.len);
}

test "candidateUrls: robots sitemaps returned first" {
    const robots_sitemaps = [_][]const u8{
        "https://example.com/custom-sitemap.xml",
    };
    const result = try candidateUrls("https://example.com", &robots_sitemaps, std.testing.allocator);
    defer {
        for (result) |u| std.testing.allocator.free(u);
        std.testing.allocator.free(result);
    }

    try std.testing.expect(result.len > 0);
    try std.testing.expectEqualStrings("https://example.com/custom-sitemap.xml", result[0]);
}

test "candidateUrls: falls back to common paths when no robots sitemaps" {
    const result = try candidateUrls("https://example.com", &.{}, std.testing.allocator);
    defer {
        for (result) |u| std.testing.allocator.free(u);
        std.testing.allocator.free(result);
    }

    try std.testing.expect(result.len >= 2);
    try std.testing.expectEqualStrings("https://example.com/sitemap.xml", result[0]);
    try std.testing.expectEqualStrings("https://example.com/sitemap_index.xml", result[1]);
}

test "candidateUrls: robots sitemaps come before common paths" {
    const robots_sitemaps = [_][]const u8{"https://example.com/robots-sitemap.xml"};
    const result = try candidateUrls("https://example.com", &robots_sitemaps, std.testing.allocator);
    defer {
        for (result) |u| std.testing.allocator.free(u);
        std.testing.allocator.free(result);
    }

    // robots sitemap first, common paths after
    try std.testing.expectEqualStrings("https://example.com/robots-sitemap.xml", result[0]);
    try std.testing.expectEqualStrings("https://example.com/sitemap.xml", result[1]);
}
