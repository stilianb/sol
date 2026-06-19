const std = @import("std");
const c = @import("../xml.zig").c;
const h = @import("../xml_helpers.zig");
const html = @import("../parser/html.zig");

// ── types ─────────────────────────────────────────────────────────────────────

pub const SeoData = struct {
    canonical: ?[]const u8,
    has_noindex: bool,
    has_nofollow: bool,
    og_title: ?[]const u8,
    og_description: ?[]const u8,
    og_image: ?[]const u8,
    has_structured_data: bool,
    title_length: usize,
    description_length: usize,
    allocator: std.mem.Allocator,

    pub fn deinit(self: SeoData) void {
        if (self.canonical) |s| self.allocator.free(s);
        if (self.og_title) |s| self.allocator.free(s);
        if (self.og_description) |s| self.allocator.free(s);
        if (self.og_image) |s| self.allocator.free(s);
    }
};

// ── extract ───────────────────────────────────────────────────────────────────

pub fn extract(doc: html.HtmlDoc, allocator: std.mem.Allocator) !SeoData {
    const d = doc.inner;

    const canonical = h.xpathText(d, "//link[@rel='canonical']/@href", allocator);
    errdefer if (canonical) |s| allocator.free(s);

    const robots_content = h.xpathText(d, "//meta[@name='robots']/@content", allocator);
    defer if (robots_content) |r| allocator.free(r);
    const has_noindex = if (robots_content) |r| containsCI(r, "noindex") else false;
    const has_nofollow = if (robots_content) |r| containsCI(r, "nofollow") else false;

    const og_title = h.xpathText(d, "//meta[@property='og:title']/@content", allocator);
    errdefer if (og_title) |s| allocator.free(s);
    const og_description = h.xpathText(d, "//meta[@property='og:description']/@content", allocator);
    errdefer if (og_description) |s| allocator.free(s);
    const og_image = h.xpathText(d, "//meta[@property='og:image']/@content", allocator);
    errdefer if (og_image) |s| allocator.free(s);

    const has_structured_data = h.xpathCount(d, "//script[@type='application/ld+json']") > 0;

    const title_text = h.xpathText(d, "//title", allocator);
    defer if (title_text) |t| allocator.free(t);
    const title_length = if (title_text) |t| t.len else 0;

    const desc_text = h.xpathText(d, "//meta[@name='description']/@content", allocator);
    defer if (desc_text) |t| allocator.free(t);
    const description_length = if (desc_text) |t| t.len else 0;

    return .{
        .canonical = canonical,
        .has_noindex = has_noindex,
        .has_nofollow = has_nofollow,
        .og_title = og_title,
        .og_description = og_description,
        .og_image = og_image,
        .has_structured_data = has_structured_data,
        .title_length = title_length,
        .description_length = description_length,
        .allocator = allocator,
    };
}

fn containsCI(haystack: []const u8, needle: []const u8) bool {
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

// ── tests ─────────────────────────────────────────────────────────────────────

test "seo canonical extracted (mobile fixture)" {
    const HTML = "<html><head><link rel=\"canonical\" href=\"https://example.com/page\"/></head><body></body></html>";
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, std.testing.allocator);
    defer data.deinit();
    try std.testing.expectEqualStrings("https://example.com/page", data.canonical orelse return error.NoCanonical);
}

test "seo noindex and nofollow detection (mobile fixture)" {
    const HTML = "<html><head><meta name=\"robots\" content=\"noindex, nofollow\"/></head><body></body></html>";
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, std.testing.allocator);
    defer data.deinit();
    try std.testing.expect(data.has_noindex);
    try std.testing.expect(data.has_nofollow);
}

test "seo og:title extracted (mobile fixture)" {
    const HTML = "<html><head><meta property=\"og:title\" content=\"My Page\"/></head><body></body></html>";
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, std.testing.allocator);
    defer data.deinit();
    try std.testing.expectEqualStrings("My Page", data.og_title orelse return error.NoOgTitle);
}

test "seo structured data presence detected (mobile fixture)" {
    const HTML = "<html><head><script type=\"application/ld+json\">{\"@type\":\"WebSite\"}</script></head><body></body></html>";
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, std.testing.allocator);
    defer data.deinit();
    try std.testing.expect(data.has_structured_data);
}

test "seo title length counted (mobile fixture)" {
    const HTML = "<html><head><title>Hello World</title></head><body></body></html>";
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, std.testing.allocator);
    defer data.deinit();
    try std.testing.expectEqual(@as(usize, 11), data.title_length);
}
