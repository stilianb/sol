const std = @import("std");
const c = @import("../xml.zig").c;
const h = @import("../xml_helpers.zig");

// ── types ─────────────────────────────────────────────────────────────────────

pub const Link = struct {
    href: []const u8,
    is_internal: bool,
};

pub const Heading = struct {
    level: u8,
    text: []const u8,
};

// ── private helpers ───────────────────────────────────────────────────────────

fn parseRaw(html: []const u8) ?*c.xmlDoc {
    return c.htmlReadMemory(
        html.ptr,
        @intCast(html.len),
        null,
        null,
        c.HTML_PARSE_NOERROR | c.HTML_PARSE_NOWARNING,
    );
}

fn isInternalLink(href: []const u8, base_url: []const u8) bool {
    if (href.len == 0) return false;
    if (href[0] == '/' or href[0] == '#') return true;
    if (std.mem.startsWith(u8, href, "mailto:")) return false;
    if (std.mem.startsWith(u8, href, "tel:")) return false;
    if (std.mem.startsWith(u8, href, "javascript:")) return false;
    const base_host = h.extractHostname(base_url) orelse return false;
    const href_host = h.extractHostname(href) orelse return false;
    return std.mem.eql(u8, base_host, href_host);
}

fn extractLinks(doc: *c.xmlDoc, allocator: std.mem.Allocator) []const []const u8 {
    const ctx = c.xmlXPathNewContext(doc) orelse return &.{};
    defer c.xmlXPathFreeContext(ctx);
    const obj = c.xmlXPathEvalExpression("//a/@href", ctx) orelse return &.{};
    defer c.xmlXPathFreeObject(obj);
    const nodes = obj.*.nodesetval orelse return &.{};
    const count: usize = @intCast(nodes.*.nodeNr);
    if (count == 0) return &.{};
    var list: std.ArrayList([]const u8) = .empty;
    for (0..count) |i| {
        const node = nodes.*.nodeTab[i] orelse continue;
        const raw = c.xmlNodeGetContent(node) orelse continue;
        defer c.xmlFree.?(raw);
        const text = std.mem.span(@as([*:0]const u8, @ptrCast(raw)));
        const dupe = allocator.dupe(u8, text) catch continue;
        list.append(allocator, dupe) catch {
            allocator.free(dupe);
            continue;
        };
    }
    return list.toOwnedSlice(allocator) catch &.{};
}

// ── public API ────────────────────────────────────────────────────────────────

pub const HtmlDoc = struct {
    inner: *c.xmlDoc,

    pub fn deinit(self: HtmlDoc) void {
        c.xmlFreeDoc(self.inner);
    }

    pub fn title(self: HtmlDoc, allocator: std.mem.Allocator) ?[]const u8 {
        return h.xpathText(self.inner, "//title", allocator);
    }

    pub fn metaDescription(self: HtmlDoc, allocator: std.mem.Allocator) ?[]const u8 {
        return h.xpathText(self.inner, "//meta[@name='description']/@content", allocator);
    }

    pub fn h1(self: HtmlDoc, allocator: std.mem.Allocator) ?[]const u8 {
        return h.xpathText(self.inner, "//h1", allocator);
    }

    pub fn links(self: HtmlDoc, allocator: std.mem.Allocator) []const []const u8 {
        return extractLinks(self.inner, allocator);
    }

    pub fn classifiedLinks(self: HtmlDoc, base_url: []const u8, allocator: std.mem.Allocator) []const Link {
        const hrefs = extractLinks(self.inner, allocator);
        defer {
            for (hrefs) |href| allocator.free(href);
            allocator.free(hrefs);
        }
        var list: std.ArrayList(Link) = .empty;
        for (hrefs) |href| {
            const owned = allocator.dupe(u8, href) catch continue;
            list.append(allocator, .{
                .href = owned,
                .is_internal = isInternalLink(href, base_url),
            }) catch {
                allocator.free(owned);
                continue;
            };
        }
        return list.toOwnedSlice(allocator) catch &.{};
    }

    pub fn headings(self: HtmlDoc, allocator: std.mem.Allocator) []const Heading {
        const ctx = c.xmlXPathNewContext(self.inner) orelse return &.{};
        defer c.xmlXPathFreeContext(ctx);
        const obj = c.xmlXPathEvalExpression("//h1|//h2|//h3|//h4|//h5|//h6", ctx) orelse return &.{};
        defer c.xmlXPathFreeObject(obj);
        const nodes = obj.*.nodesetval orelse return &.{};
        const count: usize = @intCast(nodes.*.nodeNr);
        if (count == 0) return &.{};
        var list: std.ArrayList(Heading) = .empty;
        for (0..count) |i| {
            const node = nodes.*.nodeTab[i] orelse continue;
            const name = std.mem.span(@as([*:0]const u8, @ptrCast(node.*.name)));
            if (name.len != 2 or name[0] != 'h') continue;
            const level = name[1] - '0';
            if (level < 1 or level > 6) continue;
            const text = h.nodeText(node, allocator) orelse continue;
            list.append(allocator, .{ .level = level, .text = text }) catch {
                allocator.free(text);
                continue;
            };
        }
        return list.toOwnedSlice(allocator) catch &.{};
    }
};

pub fn parse(html: []const u8) ?HtmlDoc {
    c.xmlInitParser();
    const doc = parseRaw(html) orelse return null;
    return .{ .inner = doc };
}

// ── tests ─────────────────────────────────────────────────────────────────────

const TEST_HTML =
    \\<html>
    \\<head>
    \\  <title>Hello Sol</title>
    \\  <meta name="description" content="A test description">
    \\</head>
    \\<body>
    \\  <h1>Main Heading</h1>
    \\  <h2>Sub Heading</h2>
    \\  <h3>Deep Heading</h3>
    \\  <h2>Another Sub</h2>
    \\  <a href="https://example.com">External</a>
    \\  <a href="/internal">Internal</a>
    \\  <a href="/another">Another</a>
    \\</body>
    \\</html>
;

test "title" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = parse(TEST_HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const result = doc.title(std.testing.allocator);
    defer if (result) |t| std.testing.allocator.free(t);
    try std.testing.expectEqualStrings("Hello Sol", result orelse return error.Missing);
}

test "title null when absent" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = parse("<html><body></body></html>") orelse return error.ParseFailed;
    defer doc.deinit();
    try std.testing.expect(doc.title(std.testing.allocator) == null);
}

test "metaDescription" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = parse(TEST_HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const result = doc.metaDescription(std.testing.allocator);
    defer if (result) |t| std.testing.allocator.free(t);
    try std.testing.expectEqualStrings("A test description", result orelse return error.Missing);
}

test "metaDescription null when absent" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = parse("<html><head></head></html>") orelse return error.ParseFailed;
    defer doc.deinit();
    try std.testing.expect(doc.metaDescription(std.testing.allocator) == null);
}

test "h1" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = parse(TEST_HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const result = doc.h1(std.testing.allocator);
    defer if (result) |t| std.testing.allocator.free(t);
    try std.testing.expectEqualStrings("Main Heading", result orelse return error.Missing);
}

test "links" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = parse(TEST_HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const result = doc.links(std.testing.allocator);
    defer { for (result) |l| std.testing.allocator.free(l); std.testing.allocator.free(result); }
    try std.testing.expectEqual(@as(usize, 3), result.len);
    try std.testing.expectEqualStrings("https://example.com", result[0]);
    try std.testing.expectEqualStrings("/internal", result[1]);
}

test "classifiedLinks" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const html_src =
        \\<html><body>
        \\  <a href="/page">Rel</a>
        \\  <a href="https://example.com/page">Same</a>
        \\  <a href="https://other.com">Ext</a>
        \\</body></html>
    ;
    const doc = parse(html_src) orelse return error.ParseFailed;
    defer doc.deinit();
    const result = doc.classifiedLinks("https://example.com", std.testing.allocator);
    defer { for (result) |l| std.testing.allocator.free(l.href); std.testing.allocator.free(result); }
    try std.testing.expectEqual(@as(usize, 3), result.len);
    try std.testing.expect(result[0].is_internal);
    try std.testing.expect(result[1].is_internal);
    try std.testing.expect(!result[2].is_internal);
}

test "headings in document order" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = parse(TEST_HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const result = doc.headings(std.testing.allocator);
    defer { for (result) |hd| std.testing.allocator.free(hd.text); std.testing.allocator.free(result); }
    try std.testing.expectEqual(@as(usize, 4), result.len);
    try std.testing.expectEqual(@as(u8, 1), result[0].level);
    try std.testing.expectEqualStrings("Main Heading", result[0].text);
    try std.testing.expectEqual(@as(u8, 2), result[1].level);
    try std.testing.expectEqual(@as(u8, 3), result[2].level);
    try std.testing.expectEqual(@as(u8, 2), result[3].level);
}
