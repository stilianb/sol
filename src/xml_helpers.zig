const std = @import("std");
const c = @import("xml.zig").c;

// ── URL helpers ───────────────────────────────────────────────────────────────

pub fn extractHostname(url: []const u8) ?[]const u8 {
    const sep = std.mem.indexOf(u8, url, "://") orelse return null;
    const rest = url[sep + 3 ..];
    const end = std.mem.indexOf(u8, rest, "/") orelse rest.len;
    return rest[0..end];
}

pub fn extractOrigin(url: []const u8) ?[]const u8 {
    const sep = std.mem.indexOf(u8, url, "://") orelse return null;
    const rest = url[sep + 3 ..];
    const slash = std.mem.indexOf(u8, rest, "/") orelse return url;
    return url[0 .. sep + 3 + slash];
}

pub fn isThirdParty(src: []const u8, base_host: []const u8) bool {
    if (src.len == 0 or src[0] == '/' or src[0] == '.') return false;
    if (std.mem.startsWith(u8, src, "data:")) return false;
    const src_host = extractHostname(src) orelse return false;
    return !std.mem.eql(u8, src_host, base_host);
}

// ── Node access ───────────────────────────────────────────────────────────────

pub fn nodeLocalName(node: *c.xmlNode) []const u8 {
    return std.mem.span(@as([*:0]const u8, @ptrCast(node.*.name)));
}

/// Returns attribute value; caller must free with allocator.free.
pub fn getAttrText(node: *c.xmlNode, name: [*:0]const u8, allocator: std.mem.Allocator) ?[]const u8 {
    const raw = c.xmlGetProp(node, name) orelse return null;
    defer c.xmlFree.?(raw);
    const text = std.mem.span(@as([*:0]const u8, @ptrCast(raw)));
    return allocator.dupe(u8, text) catch null;
}

pub fn hasAttr(node: *c.xmlNode, name: [*:0]const u8) bool {
    return c.xmlHasProp(node, name) != null;
}

/// Trims whitespace; returns null if empty. Caller must free.
pub fn nodeText(node: *c.xmlNode, allocator: std.mem.Allocator) ?[]const u8 {
    const raw = c.xmlNodeGetContent(node) orelse return null;
    defer c.xmlFree.?(raw);
    const text = std.mem.trim(u8, std.mem.span(@as([*:0]const u8, @ptrCast(raw))), " \t\n\r");
    if (text.len == 0) return null;
    return allocator.dupe(u8, text) catch null;
}

/// Preserves whitespace (for measuring inline script/style bytes). Caller must free.
pub fn nodeContent(node: *c.xmlNode, allocator: std.mem.Allocator) ?[]const u8 {
    const raw = c.xmlNodeGetContent(node) orelse return null;
    defer c.xmlFree.?(raw);
    const text = std.mem.span(@as([*:0]const u8, @ptrCast(raw)));
    return allocator.dupe(u8, text) catch null;
}

// ── XPath ─────────────────────────────────────────────────────────────────────

/// Returns text of first match, or null. Caller must free.
pub fn xpathText(doc: *c.xmlDoc, expr: [*:0]const u8, allocator: std.mem.Allocator) ?[]const u8 {
    const ctx = c.xmlXPathNewContext(doc) orelse return null;
    defer c.xmlXPathFreeContext(ctx);
    const obj = c.xmlXPathEvalExpression(expr, ctx) orelse return null;
    defer c.xmlXPathFreeObject(obj);
    const nodes = obj.*.nodesetval orelse return null;
    if (nodes.*.nodeNr == 0) return null;
    const node = nodes.*.nodeTab[0] orelse return null;
    const raw = c.xmlNodeGetContent(node) orelse return null;
    defer c.xmlFree.?(raw);
    const text = std.mem.span(@as([*:0]const u8, @ptrCast(raw)));
    return allocator.dupe(u8, text) catch null;
}

pub fn xpathCount(doc: *c.xmlDoc, expr: [*:0]const u8) usize {
    const ctx = c.xmlXPathNewContext(doc) orelse return 0;
    defer c.xmlXPathFreeContext(ctx);
    const obj = c.xmlXPathEvalExpression(expr, ctx) orelse return 0;
    defer c.xmlXPathFreeObject(obj);
    const nodes = obj.*.nodesetval orelse return 0;
    return @intCast(nodes.*.nodeNr);
}

pub fn cleanupParser() void {
    c.xmlCleanupParser();
}

// ── tests ─────────────────────────────────────────────────────────────────────

test "extractHostname" {
    try std.testing.expectEqualStrings("example.com", extractHostname("https://example.com/path") orelse return error.Null);
    try std.testing.expectEqualStrings("sub.example.com", extractHostname("http://sub.example.com/") orelse return error.Null);
    try std.testing.expect(extractHostname("not-a-url") == null);
}

test "extractOrigin" {
    try std.testing.expectEqualStrings("https://example.com", extractOrigin("https://example.com/path/to/page") orelse return error.Null);
    try std.testing.expectEqualStrings("https://example.com", extractOrigin("https://example.com") orelse return error.Null);
}

test "isThirdParty" {
    try std.testing.expect(!isThirdParty("/local.js", "example.com"));
    try std.testing.expect(!isThirdParty("https://example.com/bundle.js", "example.com"));
    try std.testing.expect(isThirdParty("https://cdn.other.com/lib.js", "example.com"));
    try std.testing.expect(!isThirdParty("data:text/javascript;base64,abc", "example.com"));
}

test "xpathText and xpathCount" {
    c.xmlInitParser();
    defer cleanupParser();
    const html =
        \\<html><head><title>Hello</title></head><body>
        \\  <h1>One</h1><h2>Two</h2>
        \\</body></html>
    ;
    const doc = c.htmlReadMemory(html.ptr, @intCast(html.len), null, null, c.HTML_PARSE_NOERROR | c.HTML_PARSE_NOWARNING) orelse return error.ParseFailed;
    defer c.xmlFreeDoc(doc);

    const title = xpathText(doc, "//title", std.testing.allocator) orelse return error.Missing;
    defer std.testing.allocator.free(title);
    try std.testing.expectEqualStrings("Hello", title);

    try std.testing.expectEqual(@as(usize, 1), xpathCount(doc, "//h1"));
    try std.testing.expectEqual(@as(usize, 2), xpathCount(doc, "//h1|//h2"));
}
