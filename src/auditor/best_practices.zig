const std = @import("std");
const c = @import("../xml.zig").c;
const h = @import("../xml_helpers.zig");
const html = @import("../parser/html.zig");

// ── types ─────────────────────────────────────────────────────────────────────

pub const BestPracticesData = struct {
    is_https: bool,
    mixed_content_count: usize,
    deprecated_tag_count: usize,
    redirect_chain_depth: usize,
    allocator: std.mem.Allocator,

    pub fn deinit(self: BestPracticesData) void {
        _ = self;
    }
};

// ── extract ───────────────────────────────────────────────────────────────────

pub fn extract(
    doc: html.HtmlDoc,
    page_url: []const u8,
    redirect_depth: usize,
    allocator: std.mem.Allocator,
) !BestPracticesData {
    const d = doc.inner;

    const is_https = std.mem.startsWith(u8, page_url, "https://");

    const mixed_content_count: usize = if (is_https)
        h.xpathCount(d, "//*[@src[starts-with(., 'http://')] or @href[starts-with(., 'http://')]]")
    else
        0;

    const deprecated_tag_count = h.xpathCount(d, "//font | //center | //marquee");

    return .{
        .is_https = is_https,
        .mixed_content_count = mixed_content_count,
        .deprecated_tag_count = deprecated_tag_count,
        .redirect_chain_depth = redirect_depth,
        .allocator = allocator,
    };
}

// ── tests ─────────────────────────────────────────────────────────────────────

test "bp is_https true for https URL (mobile fixture)" {
    const HTML = "<html><body></body></html>";
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "https://example.com/", 0, std.testing.allocator);
    defer data.deinit();
    try std.testing.expect(data.is_https);
}

test "bp is_https false for http URL (mobile fixture)" {
    const HTML = "<html><body></body></html>";
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "http://example.com/", 0, std.testing.allocator);
    defer data.deinit();
    try std.testing.expect(!data.is_https);
}

test "bp deprecated font tag detected (mobile fixture)" {
    const HTML = "<html><body><font color=\"red\">text</font></body></html>";
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "https://example.com/", 0, std.testing.allocator);
    defer data.deinit();
    try std.testing.expectEqual(@as(usize, 1), data.deprecated_tag_count);
}

test "bp mixed content detected on https page (mobile fixture)" {
    const HTML = "<html><body><img src=\"http://cdn.example.com/img.jpg\"/></body></html>";
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "https://example.com/", 0, std.testing.allocator);
    defer data.deinit();
    try std.testing.expectEqual(@as(usize, 1), data.mixed_content_count);
}

test "bp redirect chain depth stored (mobile fixture)" {
    const HTML = "<html><body></body></html>";
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "https://example.com/", 2, std.testing.allocator);
    defer data.deinit();
    try std.testing.expectEqual(@as(usize, 2), data.redirect_chain_depth);
}
