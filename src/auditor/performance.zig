const std = @import("std");
const c = @import("../xml.zig").c;
const h = @import("../xml_helpers.zig");
const html = @import("../parser/html.zig");

// ── types ─────────────────────────────────────────────────────────────────────

pub const PerformanceData = struct {
    fetch_duration_ms: u64,
    html_bytes: usize,
    external_scripts: usize,
    render_blocking_scripts: usize,
    inline_scripts: usize,
    inline_script_bytes: usize,
    async_scripts: usize,
    defer_scripts: usize,
    external_stylesheets: usize,
    inline_styles: usize,
    inline_style_bytes: usize,
    image_count: usize,
    images_missing_dimensions: usize,
    preload_count: usize,
    prefetch_count: usize,
    preconnect_count: usize,
    dns_prefetch_count: usize,
    third_party_domains: []const []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: PerformanceData) void {
        for (self.third_party_domains) |d| self.allocator.free(d);
        self.allocator.free(self.third_party_domains);
    }
};

// ── extract ───────────────────────────────────────────────────────────────────

pub fn extract(
    doc: html.HtmlDoc,
    base_url: []const u8,
    fetch_duration_ms: u64,
    html_bytes: usize,
    allocator: std.mem.Allocator,
) !PerformanceData {
    const raw = doc.inner;
    const base_host = h.extractHostname(base_url) orelse "";

    var third_party_set: std.StringHashMap(void) = .init(allocator);
    defer third_party_set.deinit();

    // scripts
    var external_scripts: usize = 0;
    var render_blocking_scripts: usize = 0;
    var inline_scripts: usize = 0;
    var inline_script_bytes: usize = 0;
    var async_scripts: usize = 0;
    var defer_scripts: usize = 0;
    {
        const ctx = c.xmlXPathNewContext(raw) orelse return error.OutOfMemory;
        defer c.xmlXPathFreeContext(ctx);
        const obj = c.xmlXPathEvalExpression("//script", ctx);
        if (obj != null) {
            defer c.xmlXPathFreeObject(obj);
            const nodes = obj.?.*.nodesetval;
            if (nodes != null) {
                const count: usize = @intCast(nodes.?.*.nodeNr);
                for (0..count) |i| {
                    const node = nodes.?.*.nodeTab[i] orelse continue;
                    const src = h.getAttrText(node, "src", allocator);
                    defer if (src) |s| allocator.free(s);
                    const has_async = h.hasAttr(node, "async");
                    const has_defer = h.hasAttr(node, "defer");
                    if (src != null and src.?.len > 0) {
                        external_scripts += 1;
                        if (!has_async and !has_defer) render_blocking_scripts += 1;
                        if (has_async) async_scripts += 1;
                        if (has_defer) defer_scripts += 1;
                        if (h.isThirdParty(src.?, base_host)) {
                            if (h.extractHostname(src.?)) |host| {
                                const owned = try allocator.dupe(u8, host);
                                const result = try third_party_set.getOrPut(owned);
                                if (result.found_existing) allocator.free(owned);
                            }
                        }
                    } else {
                        const content = h.nodeContent(node, allocator);
                        defer if (content) |ct| allocator.free(ct);
                        inline_scripts += 1;
                        if (content) |ct| inline_script_bytes += ct.len;
                    }
                }
            }
        }
    }

    // external stylesheets
    var external_stylesheets: usize = 0;
    {
        const ctx = c.xmlXPathNewContext(raw) orelse return error.OutOfMemory;
        defer c.xmlXPathFreeContext(ctx);
        const obj = c.xmlXPathEvalExpression("//link[@rel='stylesheet']", ctx);
        if (obj != null) {
            defer c.xmlXPathFreeObject(obj);
            const nodes = obj.?.*.nodesetval;
            if (nodes != null) {
                const count: usize = @intCast(nodes.?.*.nodeNr);
                for (0..count) |i| {
                    const node = nodes.?.*.nodeTab[i] orelse continue;
                    const href = h.getAttrText(node, "href", allocator);
                    defer if (href) |hv| allocator.free(hv);
                    if (href != null and href.?.len > 0) {
                        external_stylesheets += 1;
                        if (h.isThirdParty(href.?, base_host)) {
                            if (h.extractHostname(href.?)) |host| {
                                const owned = try allocator.dupe(u8, host);
                                const result = try third_party_set.getOrPut(owned);
                                if (result.found_existing) allocator.free(owned);
                            }
                        }
                    }
                }
            }
        }
    }

    // inline styles
    var inline_styles: usize = 0;
    var inline_style_bytes: usize = 0;
    {
        const ctx = c.xmlXPathNewContext(raw) orelse return error.OutOfMemory;
        defer c.xmlXPathFreeContext(ctx);
        const obj = c.xmlXPathEvalExpression("//style", ctx);
        if (obj != null) {
            defer c.xmlXPathFreeObject(obj);
            const nodes = obj.?.*.nodesetval;
            if (nodes != null) {
                const count: usize = @intCast(nodes.?.*.nodeNr);
                for (0..count) |i| {
                    const node = nodes.?.*.nodeTab[i] orelse continue;
                    const content = h.nodeContent(node, allocator);
                    defer if (content) |ct| allocator.free(ct);
                    inline_styles += 1;
                    if (content) |ct| inline_style_bytes += ct.len;
                }
            }
        }
    }

    // images
    var image_count: usize = 0;
    var images_missing_dimensions: usize = 0;
    {
        const ctx = c.xmlXPathNewContext(raw) orelse return error.OutOfMemory;
        defer c.xmlXPathFreeContext(ctx);
        const obj = c.xmlXPathEvalExpression("//img", ctx);
        if (obj != null) {
            defer c.xmlXPathFreeObject(obj);
            const nodes = obj.?.*.nodesetval;
            if (nodes != null) {
                const count: usize = @intCast(nodes.?.*.nodeNr);
                image_count = count;
                for (0..count) |i| {
                    const node = nodes.?.*.nodeTab[i] orelse continue;
                    if (!h.hasAttr(node, "width") or !h.hasAttr(node, "height"))
                        images_missing_dimensions += 1;
                }
            }
        }
    }

    // resource hints
    var preload_count: usize = 0;
    var prefetch_count: usize = 0;
    var preconnect_count: usize = 0;
    var dns_prefetch_count: usize = 0;
    {
        const ctx = c.xmlXPathNewContext(raw) orelse return error.OutOfMemory;
        defer c.xmlXPathFreeContext(ctx);
        const obj = c.xmlXPathEvalExpression("//link[@rel]", ctx);
        if (obj != null) {
            defer c.xmlXPathFreeObject(obj);
            const nodes = obj.?.*.nodesetval;
            if (nodes != null) {
                const count: usize = @intCast(nodes.?.*.nodeNr);
                for (0..count) |i| {
                    const node = nodes.?.*.nodeTab[i] orelse continue;
                    const rel = h.getAttrText(node, "rel", allocator) orelse continue;
                    defer allocator.free(rel);
                    if (std.mem.eql(u8, rel, "preload")) preload_count += 1
                    else if (std.mem.eql(u8, rel, "prefetch")) prefetch_count += 1
                    else if (std.mem.eql(u8, rel, "preconnect")) preconnect_count += 1
                    else if (std.mem.eql(u8, rel, "dns-prefetch")) dns_prefetch_count += 1;
                }
            }
        }
    }

    var third_party_list: std.ArrayList([]const u8) = .empty;
    var it = third_party_set.keyIterator();
    while (it.next()) |key| try third_party_list.append(allocator, key.*);

    return .{
        .fetch_duration_ms = fetch_duration_ms,
        .html_bytes = html_bytes,
        .external_scripts = external_scripts,
        .render_blocking_scripts = render_blocking_scripts,
        .inline_scripts = inline_scripts,
        .inline_script_bytes = inline_script_bytes,
        .async_scripts = async_scripts,
        .defer_scripts = defer_scripts,
        .external_stylesheets = external_stylesheets,
        .inline_styles = inline_styles,
        .inline_style_bytes = inline_style_bytes,
        .image_count = image_count,
        .images_missing_dimensions = images_missing_dimensions,
        .preload_count = preload_count,
        .prefetch_count = prefetch_count,
        .preconnect_count = preconnect_count,
        .dns_prefetch_count = dns_prefetch_count,
        .third_party_domains = try third_party_list.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

// ── tests ─────────────────────────────────────────────────────────────────────

const TEST_HTML =
    \\<html>
    \\<head>
    \\  <script src="https://analytics.google.com/ga.js"></script>
    \\  <script src="/local.js" defer></script>
    \\  <script src="/bundle.js" async></script>
    \\  <script>var x = 1; var y = 2;</script>
    \\  <link rel="stylesheet" href="https://fonts.googleapis.com/css">
    \\  <link rel="stylesheet" href="/main.css">
    \\  <style>body { color: red; }</style>
    \\  <link rel="preload" href="/font.woff2" as="font">
    \\  <link rel="preconnect" href="https://fonts.googleapis.com">
    \\  <link rel="dns-prefetch" href="//cdn.example.com">
    \\</head>
    \\<body>
    \\  <img src="logo.png" width="100" height="50">
    \\  <img src="photo.jpg">
    \\</body>
    \\</html>
;

test "extract: script counts" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = html.parse(TEST_HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "https://example.com", 120, 4096, std.testing.allocator);
    defer data.deinit();
    try std.testing.expectEqual(@as(usize, 3), data.external_scripts);
    try std.testing.expectEqual(@as(usize, 1), data.inline_scripts);
    try std.testing.expectEqual(@as(usize, 1), data.render_blocking_scripts);
    try std.testing.expectEqual(@as(usize, 1), data.async_scripts);
    try std.testing.expectEqual(@as(usize, 1), data.defer_scripts);
}

test "extract: stylesheet counts" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = html.parse(TEST_HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "https://example.com", 120, 4096, std.testing.allocator);
    defer data.deinit();
    try std.testing.expectEqual(@as(usize, 2), data.external_stylesheets);
    try std.testing.expectEqual(@as(usize, 1), data.inline_styles);
    try std.testing.expect(data.inline_style_bytes > 0);
}

test "extract: image dimensions" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = html.parse(TEST_HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "https://example.com", 120, 4096, std.testing.allocator);
    defer data.deinit();
    try std.testing.expectEqual(@as(usize, 2), data.image_count);
    try std.testing.expectEqual(@as(usize, 1), data.images_missing_dimensions);
}

test "extract: resource hints" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = html.parse(TEST_HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "https://example.com", 120, 4096, std.testing.allocator);
    defer data.deinit();
    try std.testing.expectEqual(@as(usize, 1), data.preload_count);
    try std.testing.expectEqual(@as(usize, 1), data.preconnect_count);
    try std.testing.expectEqual(@as(usize, 1), data.dns_prefetch_count);
    try std.testing.expectEqual(@as(usize, 0), data.prefetch_count);
}

test "extract: third party domains" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = html.parse(TEST_HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "https://example.com", 120, 4096, std.testing.allocator);
    defer data.deinit();
    try std.testing.expectEqual(@as(usize, 2), data.third_party_domains.len);
}

test "extract: timing passthrough" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = html.parse(TEST_HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "https://example.com", 350, 8192, std.testing.allocator);
    defer data.deinit();
    try std.testing.expectEqual(@as(u64, 350), data.fetch_duration_ms);
    try std.testing.expectEqual(@as(usize, 8192), data.html_bytes);
}
