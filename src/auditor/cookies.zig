const std = @import("std");
const c = @import("../xml.zig").c;
const h = @import("../xml_helpers.zig");
const html = @import("../parser/html.zig");

// ── types ─────────────────────────────────────────────────────────────────────

pub const TrackerCategory = enum { analytics, advertising, social, support, unknown };

pub const TrackerInfo = struct {
    domain: []const u8,
    category: TrackerCategory,
};

pub const CookieData = struct {
    third_party_script_domains: []const []const u8,
    third_party_iframe_domains: []const []const u8,
    known_trackers: []const TrackerInfo,
    has_consent_banner: bool,
    consent_tool: ?[]const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: CookieData) void {
        for (self.third_party_script_domains) |d| self.allocator.free(d);
        self.allocator.free(self.third_party_script_domains);
        for (self.third_party_iframe_domains) |d| self.allocator.free(d);
        self.allocator.free(self.third_party_iframe_domains);
        for (self.known_trackers) |t| self.allocator.free(t.domain);
        self.allocator.free(self.known_trackers);
        if (self.consent_tool) |ct| self.allocator.free(ct);
    }
};

// ── tracker database ──────────────────────────────────────────────────────────

const TrackerEntry = struct { fragment: []const u8, category: TrackerCategory };

const KNOWN_TRACKERS = [_]TrackerEntry{
    .{ .fragment = "google-analytics.com", .category = .analytics },
    .{ .fragment = "googletagmanager.com", .category = .analytics },
    .{ .fragment = "analytics.google.com", .category = .analytics },
    .{ .fragment = "googlesyndication.com", .category = .advertising },
    .{ .fragment = "doubleclick.net", .category = .advertising },
    .{ .fragment = "connect.facebook.net", .category = .advertising },
    .{ .fragment = "facebook.com/tr", .category = .advertising },
    .{ .fragment = "hotjar.com", .category = .analytics },
    .{ .fragment = "segment.com", .category = .analytics },
    .{ .fragment = "mixpanel.com", .category = .analytics },
    .{ .fragment = "amplitude.com", .category = .analytics },
    .{ .fragment = "hubspot.com", .category = .support },
    .{ .fragment = "hs-scripts.com", .category = .support },
    .{ .fragment = "intercom.io", .category = .support },
    .{ .fragment = "intercomcdn.com", .category = .support },
    .{ .fragment = "drift.com", .category = .support },
    .{ .fragment = "linkedin.com/insight", .category = .advertising },
    .{ .fragment = "snap.licdn.com", .category = .advertising },
    .{ .fragment = "analytics.twitter.com", .category = .advertising },
    .{ .fragment = "static.ads-twitter.com", .category = .advertising },
    .{ .fragment = "tiktok.com", .category = .advertising },
    .{ .fragment = "clarity.ms", .category = .analytics },
    .{ .fragment = "cdn.cookielaw.org", .category = .unknown },
    .{ .fragment = "cookiebot.com", .category = .unknown },
    .{ .fragment = "cookiefirst.com", .category = .unknown },
};

const ConsentPattern = struct { fragment: []const u8, tool: []const u8 };

const CONSENT_PATTERNS = [_]ConsentPattern{
    .{ .fragment = "cookielaw.org", .tool = "OneTrust" },
    .{ .fragment = "onetrust", .tool = "OneTrust" },
    .{ .fragment = "cookiebot", .tool = "Cookiebot" },
    .{ .fragment = "cookiefirst", .tool = "CookieFirst" },
    .{ .fragment = "cookiepro", .tool = "CookiePro" },
    .{ .fragment = "cookiehub", .tool = "CookieHub" },
    .{ .fragment = "cookiyes", .tool = "CookieYes" },
    .{ .fragment = "consent-banner", .tool = "custom" },
    .{ .fragment = "gdpr-banner", .tool = "custom" },
    .{ .fragment = "cookie-notice", .tool = "custom" },
    .{ .fragment = "cookie-consent", .tool = "custom" },
    .{ .fragment = "cookie-banner", .tool = "custom" },
    .{ .fragment = "axeptio", .tool = "Axeptio" },
    .{ .fragment = "trustarc", .tool = "TrustArc" },
    .{ .fragment = "quantcast", .tool = "Quantcast" },
};

fn matchesTracker(url: []const u8) ?TrackerEntry {
    for (KNOWN_TRACKERS) |t| {
        if (std.mem.indexOf(u8, url, t.fragment) != null) return t;
    }
    return null;
}

fn matchesConsentPattern(text: []const u8) ?[]const u8 {
    for (CONSENT_PATTERNS) |p| {
        if (std.mem.indexOf(u8, text, p.fragment) != null) return p.tool;
    }
    return null;
}

// ── extract ───────────────────────────────────────────────────────────────────

pub fn extract(
    doc: html.HtmlDoc,
    base_url: []const u8,
    allocator: std.mem.Allocator,
) !CookieData {
    const raw = doc.inner;
    const base_host = h.extractHostname(base_url) orelse "";

    var script_domains: std.StringHashMap(void) = .init(allocator);
    defer script_domains.deinit();
    var iframe_domains: std.StringHashMap(void) = .init(allocator);
    defer iframe_domains.deinit();
    var tracker_map: std.StringHashMap(TrackerCategory) = .init(allocator);
    defer tracker_map.deinit();

    var has_consent_banner = false;
    var consent_tool: ?[]const u8 = null;

    // scripts
    {
        const ctx = c.xmlXPathNewContext(raw) orelse return error.OutOfMemory;
        defer c.xmlXPathFreeContext(ctx);
        const obj = c.xmlXPathEvalExpression("//script[@src]", ctx);
        if (obj != null) {
            defer c.xmlXPathFreeObject(obj);
            const nodes = obj.?.*.nodesetval;
            if (nodes != null) {
                const count: usize = @intCast(nodes.?.*.nodeNr);
                for (0..count) |i| {
                    const node = nodes.?.*.nodeTab[i] orelse continue;
                    const src = h.getAttrText(node, "src", allocator) orelse continue;
                    defer allocator.free(src);
                    if (!h.isThirdParty(src, base_host)) continue;
                    if (!has_consent_banner) {
                        if (matchesConsentPattern(src)) |tool| {
                            has_consent_banner = true;
                            consent_tool = try allocator.dupe(u8, tool);
                        }
                    }
                    if (matchesTracker(src)) |entry| {
                        const host = h.extractHostname(src) orelse src;
                        const owned = try allocator.dupe(u8, host);
                        const result = try tracker_map.getOrPut(owned);
                        if (result.found_existing) {
                            allocator.free(owned);
                        } else {
                            result.value_ptr.* = entry.category;
                        }
                    }
                    const host = h.extractHostname(src) orelse continue;
                    const owned = try allocator.dupe(u8, host);
                    const result = try script_domains.getOrPut(owned);
                    if (result.found_existing) allocator.free(owned);
                }
            }
        }
    }

    // iframes
    {
        const ctx = c.xmlXPathNewContext(raw) orelse return error.OutOfMemory;
        defer c.xmlXPathFreeContext(ctx);
        const obj = c.xmlXPathEvalExpression("//iframe[@src]", ctx);
        if (obj != null) {
            defer c.xmlXPathFreeObject(obj);
            const nodes = obj.?.*.nodesetval;
            if (nodes != null) {
                const count: usize = @intCast(nodes.?.*.nodeNr);
                for (0..count) |i| {
                    const node = nodes.?.*.nodeTab[i] orelse continue;
                    const src = h.getAttrText(node, "src", allocator) orelse continue;
                    defer allocator.free(src);
                    if (!h.isThirdParty(src, base_host)) continue;
                    const host = h.extractHostname(src) orelse continue;
                    const owned = try allocator.dupe(u8, host);
                    const result = try iframe_domains.getOrPut(owned);
                    if (result.found_existing) allocator.free(owned);
                }
            }
        }
    }

    // DOM consent banner heuristic
    if (!has_consent_banner) {
        const ctx = c.xmlXPathNewContext(raw) orelse return error.OutOfMemory;
        defer c.xmlXPathFreeContext(ctx);
        const obj = c.xmlXPathEvalExpression("//*[@id or @class]", ctx);
        if (obj != null) {
            defer c.xmlXPathFreeObject(obj);
            const nodes = obj.?.*.nodesetval;
            if (nodes != null) {
                const count: usize = @intCast(nodes.?.*.nodeNr);
                outer: for (0..count) |i| {
                    const node = nodes.?.*.nodeTab[i] orelse continue;
                    const attrs = [_][*:0]const u8{ "id", "class" };
                    for (attrs) |attr| {
                        const val = h.getAttrText(node, attr, allocator) orelse continue;
                        defer allocator.free(val);
                        var lower_buf: [256]u8 = undefined;
                        if (val.len > lower_buf.len) continue;
                        const lower = std.ascii.lowerString(&lower_buf, val);
                        if (matchesConsentPattern(lower)) |tool| {
                            has_consent_banner = true;
                            consent_tool = try allocator.dupe(u8, tool);
                            break :outer;
                        }
                    }
                }
            }
        }
    }

    var script_list: std.ArrayList([]const u8) = .empty;
    var sit = script_domains.keyIterator();
    while (sit.next()) |key| try script_list.append(allocator, key.*);

    var iframe_list: std.ArrayList([]const u8) = .empty;
    var iit = iframe_domains.keyIterator();
    while (iit.next()) |key| try iframe_list.append(allocator, key.*);

    var tracker_list: std.ArrayList(TrackerInfo) = .empty;
    var tit = tracker_map.iterator();
    while (tit.next()) |entry| {
        try tracker_list.append(allocator, .{ .domain = entry.key_ptr.*, .category = entry.value_ptr.* });
    }

    return .{
        .third_party_script_domains = try script_list.toOwnedSlice(allocator),
        .third_party_iframe_domains = try iframe_list.toOwnedSlice(allocator),
        .known_trackers = try tracker_list.toOwnedSlice(allocator),
        .has_consent_banner = has_consent_banner,
        .consent_tool = consent_tool,
        .allocator = allocator,
    };
}

// ── tests ─────────────────────────────────────────────────────────────────────

const TEST_HTML =
    \\<html>
    \\<head>
    \\  <script src="https://www.googletagmanager.com/gtm.js?id=GTM-XXXX"></script>
    \\  <script src="https://connect.facebook.net/en_US/fbevents.js"></script>
    \\  <script src="https://cdn.cookielaw.org/consent/uuid.js"></script>
    \\  <script src="/local.js"></script>
    \\</head>
    \\<body>
    \\  <iframe src="https://www.youtube.com/embed/abc"></iframe>
    \\</body>
    \\</html>
;

test "extract: third_party_script_domains" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = html.parse(TEST_HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "https://example.com", std.testing.allocator);
    defer data.deinit();
    try std.testing.expectEqual(@as(usize, 3), data.third_party_script_domains.len);
}

test "extract: third_party_iframe_domains" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = html.parse(TEST_HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "https://example.com", std.testing.allocator);
    defer data.deinit();
    try std.testing.expectEqual(@as(usize, 1), data.third_party_iframe_domains.len);
    try std.testing.expectEqualStrings("www.youtube.com", data.third_party_iframe_domains[0]);
}

test "extract: known_trackers detected" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = html.parse(TEST_HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "https://example.com", std.testing.allocator);
    defer data.deinit();
    try std.testing.expect(data.known_trackers.len >= 2);
}

test "extract: consent banner via script src" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = html.parse(TEST_HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "https://example.com", std.testing.allocator);
    defer data.deinit();
    try std.testing.expect(data.has_consent_banner);
    try std.testing.expectEqualStrings("OneTrust", data.consent_tool orelse return error.Missing);
}

test "extract: consent banner via DOM id" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = html.parse("<html><body><div id=\"cookie-banner\">Accept?</div></body></html>") orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "https://example.com", std.testing.allocator);
    defer data.deinit();
    try std.testing.expect(data.has_consent_banner);
    try std.testing.expectEqualStrings("custom", data.consent_tool orelse return error.Missing);
}

test "extract: no consent banner" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = html.parse("<html><body><p>Hello</p></body></html>") orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "https://example.com", std.testing.allocator);
    defer data.deinit();
    try std.testing.expect(!data.has_consent_banner);
    try std.testing.expect(data.consent_tool == null);
}

test "extract: local scripts excluded" {
    c.xmlInitParser();
    defer c.xmlCleanupParser();
    const doc = html.parse("<html><head><script src='/app.js'></script></head></html>") orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "https://example.com", std.testing.allocator);
    defer data.deinit();
    try std.testing.expectEqual(@as(usize, 0), data.third_party_script_domains.len);
}
