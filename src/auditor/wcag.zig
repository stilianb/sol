const std = @import("std");
const c = @import("../xml.zig").c;
const h = @import("../xml_helpers.zig");
const html = @import("../parser/html.zig");

// ── types ─────────────────────────────────────────────────────────────────────

pub const ImageData = struct {
    src: []const u8,
    alt: ?[]const u8,
    role_presentation: bool,
};

pub const InputData = struct {
    input_type: []const u8,
    id: ?[]const u8,
    has_label_for: bool,
    has_aria_label: bool,
    has_aria_labelledby: bool,
    has_placeholder: bool,
    autocomplete: ?[]const u8,
};

pub const WcagData = struct {
    html_lang: ?[]const u8,
    has_title: bool,
    viewport_meta: ?[]const u8,
    viewport_disables_zoom: bool,
    has_skip_link: bool,
    h1_count: usize,
    heading_sequence: []const u8,
    images: []const ImageData,
    images_missing_alt: usize,
    images_empty_alt: usize,
    empty_links: usize,
    generic_links: usize,
    inputs: []const InputData,
    inputs_missing_label: usize,
    has_main_landmark: bool,
    has_nav_landmark: bool,
    tabindex_positive_count: usize,
    allocator: std.mem.Allocator,

    pub fn deinit(self: WcagData) void {
        if (self.html_lang) |s| self.allocator.free(s);
        if (self.viewport_meta) |s| self.allocator.free(s);
        self.allocator.free(self.heading_sequence);
        for (self.images) |img| {
            self.allocator.free(img.src);
            if (img.alt) |a| self.allocator.free(a);
        }
        self.allocator.free(self.images);
        for (self.inputs) |inp| {
            self.allocator.free(inp.input_type);
            if (inp.id) |id| self.allocator.free(id);
            if (inp.autocomplete) |ac| self.allocator.free(ac);
        }
        self.allocator.free(self.inputs);
    }
};

// ── helpers ───────────────────────────────────────────────────────────────────

const GENERIC_LINK_TEXTS = [_][]const u8{
    "click here", "here", "read more", "more", "link", "this", "learn more",
};

fn isGenericLinkText(text: []const u8) bool {
    var lower_buf: [64]u8 = undefined;
    if (text.len > lower_buf.len) return false;
    const lower = std.ascii.lowerString(&lower_buf, text);
    for (GENERIC_LINK_TEXTS) |g| if (std.mem.eql(u8, lower, g)) return true;
    return false;
}

// ── extract ───────────────────────────────────────────────────────────────────

pub fn extract(doc: html.HtmlDoc, allocator: std.mem.Allocator) !WcagData {
    const raw = doc.inner;

    const html_lang = h.xpathText(raw, "/html/@lang", allocator);
    const has_title = h.xpathCount(raw, "//title") > 0;
    const viewport_meta = h.xpathText(raw, "//meta[@name='viewport']/@content", allocator);
    const viewport_disables_zoom = if (viewport_meta) |vm|
        std.mem.indexOf(u8, vm, "user-scalable=no") != null or
        std.mem.indexOf(u8, vm, "maximum-scale=1") != null
    else
        false;
    const has_skip_link = h.xpathCount(raw, "//a[starts-with(@href,'#')]") > 0;
    const h1_count = h.xpathCount(raw, "//h1");

    // heading sequence
    var heading_seq: std.ArrayList(u8) = .empty;
    {
        const ctx = c.xmlXPathNewContext(raw) orelse return error.OutOfMemory;
        defer c.xmlXPathFreeContext(ctx);
        const obj = c.xmlXPathEvalExpression("//h1|//h2|//h3|//h4|//h5|//h6", ctx);
        if (obj != null) {
            defer c.xmlXPathFreeObject(obj);
            const nodes = obj.?.*.nodesetval;
            if (nodes != null) {
                const count: usize = @intCast(nodes.?.*.nodeNr);
                for (0..count) |i| {
                    const node = nodes.?.*.nodeTab[i] orelse continue;
                    const name = h.nodeLocalName(node);
                    if (name.len == 2 and name[0] == 'h') {
                        const level = name[1] - '0';
                        if (level >= 1 and level <= 6)
                            try heading_seq.append(allocator, level);
                    }
                }
            }
        }
    }

    // images
    var images: std.ArrayList(ImageData) = .empty;
    var images_missing_alt: usize = 0;
    var images_empty_alt: usize = 0;
    {
        const ctx = c.xmlXPathNewContext(raw) orelse return error.OutOfMemory;
        defer c.xmlXPathFreeContext(ctx);
        const obj = c.xmlXPathEvalExpression("//img", ctx);
        if (obj != null) {
            defer c.xmlXPathFreeObject(obj);
            const nodes = obj.?.*.nodesetval;
            if (nodes != null) {
                const count: usize = @intCast(nodes.?.*.nodeNr);
                for (0..count) |i| {
                    const node = nodes.?.*.nodeTab[i] orelse continue;
                    const src = h.getAttrText(node, "src", allocator) orelse try allocator.dupe(u8, "");
                    const role_presentation = blk: {
                        const role = c.xmlGetProp(node, "role");
                        if (role == null) break :blk false;
                        defer c.xmlFree.?(role);
                        const rs = std.mem.span(@as([*:0]const u8, @ptrCast(role)));
                        break :blk std.mem.eql(u8, rs, "presentation") or std.mem.eql(u8, rs, "none");
                    };
                    const alt_raw = c.xmlGetProp(node, "alt");
                    if (alt_raw == null) {
                        images_missing_alt += 1;
                        try images.append(allocator, .{ .src = src, .alt = null, .role_presentation = role_presentation });
                    } else {
                        defer c.xmlFree.?(alt_raw);
                        const alt_text = std.mem.span(@as([*:0]const u8, @ptrCast(alt_raw)));
                        const owned_alt = try allocator.dupe(u8, alt_text);
                        if (alt_text.len == 0) images_empty_alt += 1;
                        try images.append(allocator, .{ .src = src, .alt = owned_alt, .role_presentation = role_presentation });
                    }
                }
            }
        }
    }

    // links: empty + generic
    var empty_links: usize = 0;
    var generic_links: usize = 0;
    {
        const ctx = c.xmlXPathNewContext(raw) orelse return error.OutOfMemory;
        defer c.xmlXPathFreeContext(ctx);
        const obj = c.xmlXPathEvalExpression("//a", ctx);
        if (obj != null) {
            defer c.xmlXPathFreeObject(obj);
            const nodes = obj.?.*.nodesetval;
            if (nodes != null) {
                const count: usize = @intCast(nodes.?.*.nodeNr);
                for (0..count) |i| {
                    const node = nodes.?.*.nodeTab[i] orelse continue;
                    const text_opt = h.nodeText(node, allocator);
                    defer if (text_opt) |t| allocator.free(t);
                    if (text_opt == null or text_opt.?.len == 0) {
                        empty_links += 1;
                    } else if (isGenericLinkText(text_opt.?)) {
                        generic_links += 1;
                    }
                }
            }
        }
    }

    // inputs
    var inputs: std.ArrayList(InputData) = .empty;
    var inputs_missing_label: usize = 0;
    {
        const ctx = c.xmlXPathNewContext(raw) orelse return error.OutOfMemory;
        defer c.xmlXPathFreeContext(ctx);
        const obj = c.xmlXPathEvalExpression("//input[@type!='hidden' and @type!='submit' and @type!='button' and @type!='reset'] | //input[not(@type)]", ctx);
        if (obj != null) {
            defer c.xmlXPathFreeObject(obj);
            const label_ctx = c.xmlXPathNewContext(raw) orelse return error.OutOfMemory;
            defer c.xmlXPathFreeContext(label_ctx);
            const nodes = obj.?.*.nodesetval;
            if (nodes != null) {
                const count: usize = @intCast(nodes.?.*.nodeNr);
                for (0..count) |i| {
                    const node = nodes.?.*.nodeTab[i] orelse continue;
                    const input_type = h.getAttrText(node, "type", allocator) orelse try allocator.dupe(u8, "text");
                    const id_val = h.getAttrText(node, "id", allocator);
                    const has_aria_label = h.hasAttr(node, "aria-label");
                    const has_aria_labelledby = h.hasAttr(node, "aria-labelledby");
                    const has_placeholder = h.hasAttr(node, "placeholder");
                    const autocomplete = h.getAttrText(node, "autocomplete", allocator);
                    const has_label_for = blk: {
                        if (id_val == null) break :blk false;
                        var buf: [256]u8 = undefined;
                        const expr = std.fmt.bufPrintZ(&buf, "//label[@for='{s}']", .{id_val.?}) catch break :blk false;
                        const lobj = c.xmlXPathEvalExpression(expr.ptr, label_ctx);
                        if (lobj == null) break :blk false;
                        defer c.xmlXPathFreeObject(lobj);
                        const lnodes = lobj.?.*.nodesetval orelse break :blk false;
                        break :blk lnodes.*.nodeNr > 0;
                    };
                    if (!has_label_for and !has_aria_label and !has_aria_labelledby)
                        inputs_missing_label += 1;
                    try inputs.append(allocator, .{
                        .input_type = input_type,
                        .id = id_val,
                        .has_label_for = has_label_for,
                        .has_aria_label = has_aria_label,
                        .has_aria_labelledby = has_aria_labelledby,
                        .has_placeholder = has_placeholder,
                        .autocomplete = autocomplete,
                    });
                }
            }
        }
    }

    const has_main_landmark = h.xpathCount(raw, "//main | //*[@role='main']") > 0;
    const has_nav_landmark = h.xpathCount(raw, "//nav | //*[@role='navigation']") > 0;
    const tabindex_positive_count = h.xpathCount(raw, "//*[@tabindex > 0]");

    return .{
        .html_lang = html_lang,
        .has_title = has_title,
        .viewport_meta = viewport_meta,
        .viewport_disables_zoom = viewport_disables_zoom,
        .has_skip_link = has_skip_link,
        .h1_count = h1_count,
        .heading_sequence = try heading_seq.toOwnedSlice(allocator),
        .images = try images.toOwnedSlice(allocator),
        .images_missing_alt = images_missing_alt,
        .images_empty_alt = images_empty_alt,
        .empty_links = empty_links,
        .generic_links = generic_links,
        .inputs = try inputs.toOwnedSlice(allocator),
        .inputs_missing_label = inputs_missing_label,
        .has_main_landmark = has_main_landmark,
        .has_nav_landmark = has_nav_landmark,
        .tabindex_positive_count = tabindex_positive_count,
        .allocator = allocator,
    };
}

// ── tests ─────────────────────────────────────────────────────────────────────

const TEST_HTML =
    \\<html lang="en">
    \\<head>
    \\  <title>Test Page</title>
    \\  <meta name="viewport" content="width=device-width, initial-scale=1.0">
    \\</head>
    \\<body>
    \\  <a href="#main">Skip to content</a>
    \\  <nav><a href="/">Home</a></nav>
    \\  <main id="main">
    \\    <h1>Main Heading</h1>
    \\    <h2>Sub Heading</h2>
    \\    <h3>Deep Heading</h3>
    \\    <img src="logo.png" alt="Company Logo">
    \\    <img src="deco.png" alt="">
    \\    <img src="broken.png">
    \\    <a href="/page">Read More</a>
    \\    <a href="/about">About Us</a>
    \\    <a href="/contact"></a>
    \\    <form>
    \\      <label for="name">Name</label>
    \\      <input type="text" id="name">
    \\      <input type="email" aria-label="Email address">
    \\      <input type="text" placeholder="Search">
    \\    </form>
    \\  </main>
    \\</body>
    \\</html>
;

test "extract: html_lang" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = html.parse(TEST_HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, std.testing.allocator);
    defer data.deinit();
    try std.testing.expectEqualStrings("en", data.html_lang orelse return error.Missing);
}

test "extract: html_lang null when absent" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = html.parse("<html><body></body></html>") orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, std.testing.allocator);
    defer data.deinit();
    try std.testing.expect(data.html_lang == null);
}

test "extract: has_title" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = html.parse(TEST_HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, std.testing.allocator);
    defer data.deinit();
    try std.testing.expect(data.has_title);
}

test "extract: viewport" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = html.parse(TEST_HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, std.testing.allocator);
    defer data.deinit();
    try std.testing.expectEqualStrings("width=device-width, initial-scale=1.0", data.viewport_meta orelse return error.Missing);
    try std.testing.expect(!data.viewport_disables_zoom);
}

test "extract: viewport_disables_zoom" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = html.parse("<html><head><meta name=\"viewport\" content=\"width=device-width, user-scalable=no\"></head></html>") orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, std.testing.allocator);
    defer data.deinit();
    try std.testing.expect(data.viewport_disables_zoom);
}

test "extract: skip link and heading sequence" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = html.parse(TEST_HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, std.testing.allocator);
    defer data.deinit();
    try std.testing.expect(data.has_skip_link);
    try std.testing.expectEqual(@as(usize, 1), data.h1_count);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, data.heading_sequence);
}

test "extract: image alt audit" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = html.parse(TEST_HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, std.testing.allocator);
    defer data.deinit();
    try std.testing.expectEqual(@as(usize, 1), data.images_missing_alt);
    try std.testing.expectEqual(@as(usize, 1), data.images_empty_alt);
    try std.testing.expectEqual(@as(usize, 3), data.images.len);
}

test "extract: generic and empty links" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = html.parse(TEST_HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, std.testing.allocator);
    defer data.deinit();
    try std.testing.expectEqual(@as(usize, 1), data.generic_links);
    try std.testing.expectEqual(@as(usize, 1), data.empty_links);
}

test "extract: input labeling" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = html.parse(TEST_HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, std.testing.allocator);
    defer data.deinit();
    try std.testing.expectEqual(@as(usize, 1), data.inputs_missing_label);
    try std.testing.expect(data.inputs[0].has_label_for);
    try std.testing.expect(data.inputs[1].has_aria_label);
}

test "extract: ARIA landmarks" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = html.parse(TEST_HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, std.testing.allocator);
    defer data.deinit();
    try std.testing.expect(data.has_main_landmark);
    try std.testing.expect(data.has_nav_landmark);
}

test "extract: tabindex_positive_count" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = html.parse("<html><body><a href='/' tabindex='1'>x</a><a href='/' tabindex='2'>y</a><a href='/' tabindex='0'>z</a></body></html>") orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, std.testing.allocator);
    defer data.deinit();
    try std.testing.expectEqual(@as(usize, 2), data.tabindex_positive_count);
}
