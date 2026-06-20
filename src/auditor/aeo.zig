const std = @import("std");
const c = @import("../xml.zig").c;
const h = @import("../xml_helpers.zig");
const html = @import("../parser/html.zig");

// ── types ─────────────────────────────────────────────────────────────────────

pub const AeoData = struct {
    has_faq_schema: bool,
    has_howto_schema: bool,
    has_article_schema: bool,
    has_author_entity: bool,
    has_publisher_entity: bool,
    has_qa_headings: bool,
    outbound_link_count: usize,
    allocator: std.mem.Allocator,

    pub fn deinit(self: AeoData) void {
        _ = self;
    }
};

// ── extract ───────────────────────────────────────────────────────────────────

pub fn extract(doc: html.HtmlDoc, page_url: []const u8, allocator: std.mem.Allocator) !AeoData {
    const d = doc.inner;

    var has_faq_schema = false;
    var has_howto_schema = false;
    var has_article_schema = false;
    var has_author_entity = false;
    var has_publisher_entity = false;

    // Scan all ld+json script blocks for schema type signals and entity fields.
    {
        const ctx = c.xmlXPathNewContext(d) orelse return error.OutOfMemory;
        defer c.xmlXPathFreeContext(ctx);
        const obj = c.xmlXPathEvalExpression("//script[@type='application/ld+json']", ctx);
        if (obj != null) {
            defer c.xmlXPathFreeObject(obj);
            const nodes = obj.?.*.nodesetval;
            if (nodes != null) {
                const count: usize = @intCast(nodes.?.*.nodeNr);
                for (0..count) |i| {
                    const node = nodes.?.*.nodeTab[i] orelse continue;
                    const content = h.nodeContent(node, allocator) orelse continue;
                    defer allocator.free(content);
                    if (containsStr(content, "FAQPage")) has_faq_schema = true;
                    if (containsStr(content, "HowTo")) has_howto_schema = true;
                    if (containsStr(content, "Article") or
                        containsStr(content, "NewsArticle") or
                        containsStr(content, "BlogPosting")) has_article_schema = true;
                    if (containsStr(content, "\"author\"")) has_author_entity = true;
                    if (containsStr(content, "\"publisher\"") or
                        containsStr(content, "\"organization\"")) has_publisher_entity = true;
                }
            }
        }
    }

    // Author can also come from <meta name="author">.
    if (!has_author_entity) {
        const author_meta = h.xpathText(d, "//meta[@name='author']/@content", allocator);
        if (author_meta) |a| {
            allocator.free(a);
            has_author_entity = true;
        }
    }

    const has_qa_headings = detectQaHeadings(d, allocator);

    const page_host = h.extractHostname(page_url) orelse "";
    const outbound_link_count = countOutboundLinks(d, page_host, allocator);

    return .{
        .has_faq_schema = has_faq_schema,
        .has_howto_schema = has_howto_schema,
        .has_article_schema = has_article_schema,
        .has_author_entity = has_author_entity,
        .has_publisher_entity = has_publisher_entity,
        .has_qa_headings = has_qa_headings,
        .outbound_link_count = outbound_link_count,
        .allocator = allocator,
    };
}

// ── helpers ───────────────────────────────────────────────────────────────────

fn containsStr(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

fn detectQaHeadings(d: *c.xmlDoc, allocator: std.mem.Allocator) bool {
    const ctx = c.xmlXPathNewContext(d) orelse return false;
    defer c.xmlXPathFreeContext(ctx);
    const obj = c.xmlXPathEvalExpression("//h2|//h3|//h4", ctx) orelse return false;
    defer c.xmlXPathFreeObject(obj);
    const nodes = obj.*.nodesetval orelse return false;
    const count: usize = @intCast(nodes.*.nodeNr);
    for (0..count) |i| {
        const node = nodes.*.nodeTab[i] orelse continue;
        const text = h.nodeText(node, allocator) orelse continue;
        defer allocator.free(text);
        if (isQuestionHeading(text)) return true;
    }
    return false;
}

fn isQuestionHeading(text: []const u8) bool {
    const trimmed = std.mem.trim(u8, text, " \t\n\r");
    if (trimmed.len == 0) return false;
    if (trimmed[trimmed.len - 1] == '?') return true;
    const question_prefixes = [_][]const u8{
        "how ", "what ", "why ", "when ", "where ", "which ", "who ",
        "is ", "are ", "does ", "do ", "can ", "will ", "should ",
    };
    const check_len = @min(trimmed.len, 12);
    const prefix = trimmed[0..check_len];
    for (question_prefixes) |qp| {
        if (prefix.len >= qp.len and std.ascii.eqlIgnoreCase(prefix[0..qp.len], qp)) return true;
    }
    return false;
}

fn countOutboundLinks(d: *c.xmlDoc, page_host: []const u8, allocator: std.mem.Allocator) usize {
    const ctx = c.xmlXPathNewContext(d) orelse return 0;
    defer c.xmlXPathFreeContext(ctx);
    const obj = c.xmlXPathEvalExpression("//a", ctx) orelse return 0;
    defer c.xmlXPathFreeObject(obj);
    const nodes = obj.*.nodesetval orelse return 0;
    const count: usize = @intCast(nodes.*.nodeNr);
    var outbound: usize = 0;
    for (0..count) |i| {
        const node = nodes.*.nodeTab[i] orelse continue;
        const href = h.getAttrText(node, "href", allocator) orelse continue;
        defer allocator.free(href);
        if (h.isThirdParty(href, page_host)) outbound += 1;
    }
    return outbound;
}

// ── tests ─────────────────────────────────────────────────────────────────────

test "aeo FAQ schema detected from ld+json (mobile fixture)" {
    const HTML =
        \\<html><head>
        \\<script type="application/ld+json">{"@type":"FAQPage","mainEntity":[]}</script>
        \\</head><body></body></html>
    ;
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "https://example.com", std.testing.allocator);
    defer data.deinit();
    try std.testing.expect(data.has_faq_schema);
    try std.testing.expect(!data.has_howto_schema);
    try std.testing.expect(!data.has_article_schema);
}

test "aeo HowTo schema detected from ld+json (mobile fixture)" {
    const HTML =
        \\<html><head>
        \\<script type="application/ld+json">{"@type":"HowTo","name":"How to bake"}</script>
        \\</head><body></body></html>
    ;
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "https://example.com", std.testing.allocator);
    defer data.deinit();
    try std.testing.expect(data.has_howto_schema);
}

test "aeo Article schema detected from ld+json (mobile fixture)" {
    const HTML =
        \\<html><head>
        \\<script type="application/ld+json">{"@type":"Article","name":"My Post"}</script>
        \\</head><body></body></html>
    ;
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "https://example.com", std.testing.allocator);
    defer data.deinit();
    try std.testing.expect(data.has_article_schema);
}

test "aeo author detected from meta tag (mobile fixture)" {
    const HTML =
        \\<html><head><meta name="author" content="Jane Doe"/></head><body></body></html>
    ;
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "https://example.com", std.testing.allocator);
    defer data.deinit();
    try std.testing.expect(data.has_author_entity);
}

test "aeo author detected from ld+json field (mobile fixture)" {
    const HTML =
        \\<html><head>
        \\<script type="application/ld+json">{"@type":"Article","author":{"name":"Jane"}}</script>
        \\</head><body></body></html>
    ;
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "https://example.com", std.testing.allocator);
    defer data.deinit();
    try std.testing.expect(data.has_author_entity);
}

test "aeo publisher detected from ld+json field (mobile fixture)" {
    const HTML =
        \\<html><head>
        \\<script type="application/ld+json">{"@type":"Article","publisher":{"name":"Acme"}}</script>
        \\</head><body></body></html>
    ;
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "https://example.com", std.testing.allocator);
    defer data.deinit();
    try std.testing.expect(data.has_publisher_entity);
}

test "aeo Q&A heading detected when heading ends with question mark (mobile fixture)" {
    const HTML =
        \\<html><body><h2>How do I improve my SEO?</h2></body></html>
    ;
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "https://example.com", std.testing.allocator);
    defer data.deinit();
    try std.testing.expect(data.has_qa_headings);
}

test "aeo Q&A heading detected when heading starts with question word (mobile fixture)" {
    const HTML =
        \\<html><body><h3>What is keyword density</h3></body></html>
    ;
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "https://example.com", std.testing.allocator);
    defer data.deinit();
    try std.testing.expect(data.has_qa_headings);
}

test "aeo non-question heading does not trigger Q&A flag (mobile fixture)" {
    const HTML =
        \\<html><body><h2>Getting Started with SEO</h2></body></html>
    ;
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "https://example.com", std.testing.allocator);
    defer data.deinit();
    try std.testing.expect(!data.has_qa_headings);
}

test "aeo outbound links counted, internal links excluded (mobile fixture)" {
    const HTML =
        \\<html><body>
        \\<a href="https://example.com/internal">internal</a>
        \\<a href="https://external.org/page">external</a>
        \\<a href="/relative">relative</a>
        \\</body></html>
    ;
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "https://example.com", std.testing.allocator);
    defer data.deinit();
    try std.testing.expectEqual(@as(usize, 1), data.outbound_link_count);
}
