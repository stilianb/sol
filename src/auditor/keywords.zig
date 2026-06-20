const std = @import("std");
const c = @import("../xml.zig").c;
const h = @import("../xml_helpers.zig");
const html = @import("../parser/html.zig");

// ── types ─────────────────────────────────────────────────────────────────────

/// Coverage of a single keyword against a parsed page.
/// Scoring: title=40, h1=25, description=20, density 5–30‰=15.
pub const KeywordCoverage = struct {
    keyword: []const u8,
    in_title: bool,
    in_h1: bool,
    in_description: bool,
    density_permille: u32,
    coverage_score: u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: KeywordCoverage) void {
        self.allocator.free(self.keyword);
    }
};

pub const KeywordFreq = struct {
    word: []const u8,
    count: usize,
};

pub const KeywordData = struct {
    top_keywords: []KeywordFreq,
    target_keyword: ?[]const u8,
    target_in_title: bool,
    target_in_h1: bool,
    target_in_description: bool,
    /// Per-mille (0–1000+): (phrase_occurrences × phrase_word_count / total_words) × 1000.
    /// Zero when no target keyword is given.
    keyword_density: u32,
    total_words: usize,
    allocator: std.mem.Allocator,

    pub fn deinit(self: KeywordData) void {
        for (self.top_keywords) |kf| self.allocator.free(kf.word);
        self.allocator.free(self.top_keywords);
        if (self.target_keyword) |kw| self.allocator.free(kw);
    }
};

// ── extract ───────────────────────────────────────────────────────────────────

pub fn extract(doc: html.HtmlDoc, target_keyword: ?[]const u8, allocator: std.mem.Allocator) !KeywordData {
    const d = doc.inner;

    const body_text = try extractBodyText(d, allocator);
    defer allocator.free(body_text);

    const title_text = h.xpathText(d, "//title", allocator);
    defer if (title_text) |t| allocator.free(t);
    const h1_text = h.xpathText(d, "//h1", allocator);
    defer if (h1_text) |t| allocator.free(t);
    const desc_text = h.xpathText(d, "//meta[@name='description']/@content", allocator);
    defer if (desc_text) |t| allocator.free(t);

    // Temporary arena for word frequency map keys.
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    var word_freq = std.StringHashMap(usize).init(aa);
    var total_words: usize = 0;

    var lower_buf: [128]u8 = undefined;
    var pos: usize = 0;
    while (pos < body_text.len) {
        while (pos < body_text.len and !std.ascii.isAlphabetic(body_text[pos])) pos += 1;
        if (pos >= body_text.len) break;
        const word_start = pos;
        while (pos < body_text.len and std.ascii.isAlphabetic(body_text[pos])) pos += 1;
        const word = body_text[word_start..pos];
        if (word.len < 3 or word.len > lower_buf.len) continue;
        total_words += 1;
        for (word, 0..) |ch, i| lower_buf[i] = std.ascii.toLower(ch);
        const lower = lower_buf[0..word.len];
        if (!isStopWord(lower)) {
            const gop = try word_freq.getOrPut(lower);
            if (!gop.found_existing) {
                gop.key_ptr.* = try aa.dupe(u8, lower);
                gop.value_ptr.* = 1;
            } else {
                gop.value_ptr.* += 1;
            }
        }
    }

    // Sort map entries by frequency descending, take top 20.
    const Entry = struct { word: []const u8, count: usize };
    var entries: std.ArrayList(Entry) = .empty;
    var it = word_freq.iterator();
    while (it.next()) |kv| {
        try entries.append(aa, .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* });
    }
    std.sort.block(Entry, entries.items, {}, struct {
        fn desc(_: void, a: Entry, b: Entry) bool {
            return a.count > b.count;
        }
    }.desc);

    const top_n = @min(entries.items.len, 20);
    const top_keywords = try allocator.alloc(KeywordFreq, top_n);
    var filled: usize = 0;
    errdefer {
        for (top_keywords[0..filled]) |kf| allocator.free(kf.word);
        allocator.free(top_keywords);
    }
    for (entries.items[0..top_n]) |e| {
        top_keywords[filled] = .{
            .word = try allocator.dupe(u8, e.word),
            .count = e.count,
        };
        filled += 1;
    }

    const owned_target: ?[]const u8 = if (target_keyword) |kw|
        try normalizePhrase(kw, allocator)
    else
        null;
    errdefer if (owned_target) |kw| allocator.free(kw);

    const target_in_title = if (owned_target) |kw| containsCI(title_text orelse "", kw) else false;
    const target_in_h1 = if (owned_target) |kw| containsCI(h1_text orelse "", kw) else false;
    const target_in_description = if (owned_target) |kw| containsCI(desc_text orelse "", kw) else false;

    const density: u32 = if (owned_target) |kw| blk: {
        const phrase_occurrences = countPhrase(body_text, kw);
        const phrase_words = countWords(kw);
        if (total_words == 0 or phrase_words == 0) break :blk 0;
        break :blk @as(u32, @intCast(phrase_occurrences * phrase_words * 1000 / total_words));
    } else 0;

    return .{
        .top_keywords = top_keywords,
        .target_keyword = owned_target,
        .target_in_title = target_in_title,
        .target_in_h1 = target_in_h1,
        .target_in_description = target_in_description,
        .keyword_density = density,
        .total_words = total_words,
        .allocator = allocator,
    };
}

// ── checkKeywords ─────────────────────────────────────────────────────────────

/// Check coverage of each keyword against a parsed HTML doc.
/// Extracts body text once; caller frees the returned slice and each item via .deinit().
pub fn checkKeywords(
    doc: html.HtmlDoc,
    keywords: []const []const u8,
    allocator: std.mem.Allocator,
) ![]KeywordCoverage {
    if (keywords.len == 0) return try allocator.alloc(KeywordCoverage, 0);

    const d = doc.inner;
    const body_text = try extractBodyText(d, allocator);
    defer allocator.free(body_text);

    const title_text = h.xpathText(d, "//title", allocator);
    defer if (title_text) |t| allocator.free(t);
    const h1_text = h.xpathText(d, "//h1", allocator);
    defer if (h1_text) |t| allocator.free(t);
    const desc_text = h.xpathText(d, "//meta[@name='description']/@content", allocator);
    defer if (desc_text) |t| allocator.free(t);

    var total_words: usize = 0;
    {
        var pos: usize = 0;
        while (pos < body_text.len) {
            while (pos < body_text.len and !std.ascii.isAlphabetic(body_text[pos])) pos += 1;
            if (pos >= body_text.len) break;
            while (pos < body_text.len and std.ascii.isAlphabetic(body_text[pos])) pos += 1;
            total_words += 1;
        }
    }

    const coverages = try allocator.alloc(KeywordCoverage, keywords.len);
    var filled: usize = 0;
    errdefer {
        for (coverages[0..filled]) |kc| kc.deinit();
        allocator.free(coverages);
    }

    for (keywords) |kw| {
        const norm = try normalizePhrase(kw, allocator);
        defer allocator.free(norm);

        const in_title = containsCI(title_text orelse "", norm);
        const in_h1_val = containsCI(h1_text orelse "", norm);
        const in_desc = containsCI(desc_text orelse "", norm);

        const phrase_occ = countPhrase(body_text, norm);
        const phrase_wc = countWords(norm);
        const density: u32 = if (total_words == 0 or phrase_wc == 0) 0
        else @as(u32, @intCast(phrase_occ * phrase_wc * 1000 / total_words));

        var score: i32 = 0;
        if (in_title) score += 40;
        if (in_h1_val) score += 25;
        if (in_desc) score += 20;
        if (density >= 5 and density <= 30) score += 15;

        coverages[filled] = .{
            .keyword = try allocator.dupe(u8, kw),
            .in_title = in_title,
            .in_h1 = in_h1_val,
            .in_description = in_desc,
            .density_permille = density,
            .coverage_score = @intCast(@max(0, @min(100, score))),
            .allocator = allocator,
        };
        filled += 1;
    }

    return coverages;
}

// ── helpers ───────────────────────────────────────────────────────────────────

fn normalizePhrase(phrase: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    const trimmed = std.mem.trim(u8, phrase, " \t\n\r");
    const lower = try allocator.alloc(u8, trimmed.len);
    for (trimmed, 0..) |ch, i| lower[i] = std.ascii.toLower(ch);
    return lower;
}

fn containsCI(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

fn countPhrase(text: []const u8, phrase: []const u8) usize {
    if (phrase.len == 0) return 0;
    var count: usize = 0;
    var i: usize = 0;
    while (i + phrase.len <= text.len) {
        if (std.ascii.eqlIgnoreCase(text[i .. i + phrase.len], phrase)) {
            count += 1;
            i += phrase.len;
        } else {
            i += 1;
        }
    }
    return count;
}

fn countWords(text: []const u8) usize {
    var count: usize = 0;
    var in_word = false;
    for (text) |ch| {
        if (std.ascii.isAlphabetic(ch)) {
            if (!in_word) {
                count += 1;
                in_word = true;
            }
        } else {
            in_word = false;
        }
    }
    return count;
}

/// Extract visible text from body, skipping script/style/code/pre/noscript/template.
fn extractBodyText(doc: *c.xmlDoc, allocator: std.mem.Allocator) ![]u8 {
    const ctx = c.xmlXPathNewContext(doc) orelse return allocator.dupe(u8, "");
    defer c.xmlXPathFreeContext(ctx);
    const obj = c.xmlXPathEvalExpression("//body", ctx) orelse return allocator.dupe(u8, "");
    defer c.xmlXPathFreeObject(obj);
    const nodes = obj.*.nodesetval orelse return allocator.dupe(u8, "");
    if (nodes.*.nodeNr == 0) return allocator.dupe(u8, "");
    const body = nodes.*.nodeTab[0] orelse return allocator.dupe(u8, "");

    var buf: std.ArrayList(u8) = .empty;
    try collectText(body, &buf, allocator);
    return buf.toOwnedSlice(allocator);
}

const skip_tags = [_][]const u8{ "script", "style", "noscript", "template", "code", "pre" };

fn isSkipped(name: []const u8) bool {
    for (skip_tags) |s| if (std.ascii.eqlIgnoreCase(name, s)) return true;
    return false;
}

fn collectText(node: *c.xmlNode, buf: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    var child: ?*c.xmlNode = node.*.children;
    while (child) |n| : (child = n.*.next) {
        if (n.*.type == c.XML_TEXT_NODE) {
            if (n.*.content) |content| {
                const text = std.mem.span(@as([*:0]const u8, @ptrCast(content)));
                try buf.appendSlice(allocator, text);
                try buf.append(allocator, ' ');
            }
        } else if (n.*.type == c.XML_ELEMENT_NODE) {
            if (n.*.name) |name| {
                const tag = std.mem.span(@as([*:0]const u8, @ptrCast(name)));
                if (!isSkipped(tag)) try collectText(n, buf, allocator);
            }
        }
    }
}

fn isStopWord(word: []const u8) bool {
    const stops = [_][]const u8{
        "a",    "an",    "the",   "and",   "or",   "but",    "in",   "on",
        "at",   "to",    "for",   "of",    "with", "by",     "is",   "are",
        "was",  "were",  "be",    "been",  "being","have",   "has",  "had",
        "do",   "does",  "did",   "will",  "would","could",  "should","may",
        "might","shall", "can",   "i",     "me",   "my",     "we",   "our",
        "you",  "your",  "he",    "his",   "she",  "her",    "it",   "its",
        "they", "their", "this",  "that",  "these","those",  "from", "as",
        "into", "not",   "no",    "so",    "if",   "then",   "than", "also",
        "just", "more",  "about", "up",    "out",  "over",   "all",  "both",
        "each", "other", "some",  "such",  "only", "same",   "very", "too",
        "us",   "its",   "which", "who",   "any",  "after",  "s",    "re",
    };
    for (stops) |s| if (std.mem.eql(u8, word, s)) return true;
    return false;
}

// ── tests ─────────────────────────────────────────────────────────────────────

test "top keyword extracted from body text (mobile fixture)" {
    const HTML = "<html><body><p>cat sat on the mat the cat is a fat cat</p></body></html>";
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, null, std.testing.allocator);
    defer data.deinit();
    try std.testing.expect(data.top_keywords.len >= 1);
    try std.testing.expectEqualStrings("cat", data.top_keywords[0].word);
    try std.testing.expectEqual(@as(usize, 3), data.top_keywords[0].count);
}

test "stop words filtered from top keywords (mobile fixture)" {
    const HTML = "<html><body><p>the cat sat on the mat the cat is a fat cat</p></body></html>";
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, null, std.testing.allocator);
    defer data.deinit();
    for (data.top_keywords) |kf| {
        try std.testing.expect(!std.mem.eql(u8, kf.word, "the"));
        try std.testing.expect(!std.mem.eql(u8, kf.word, "on"));
        try std.testing.expect(!std.mem.eql(u8, kf.word, "is"));
        try std.testing.expect(!std.mem.eql(u8, kf.word, "a"));
    }
}

test "target keyword detected in title (mobile fixture)" {
    const HTML =
        \\<html><head><title>Site Audit Tool</title></head>
        \\<body></body></html>
    ;
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "site audit", std.testing.allocator);
    defer data.deinit();
    try std.testing.expect(data.target_in_title);
    try std.testing.expect(!data.target_in_h1);
}

test "target keyword detected in h1 (mobile fixture)" {
    const HTML =
        \\<html><body><h1>Keyword Rankings Guide</h1></body></html>
    ;
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "keyword rankings", std.testing.allocator);
    defer data.deinit();
    try std.testing.expect(data.target_in_h1);
}

test "target keyword detected in meta description (mobile fixture)" {
    const HTML =
        \\<html><head>
        \\<meta name="description" content="The best site audit tool for SEO"/>
        \\</head><body></body></html>
    ;
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "site audit tool", std.testing.allocator);
    defer data.deinit();
    try std.testing.expect(data.target_in_description);
}

test "keyword density measured per-mille (mobile fixture)" {
    // "quick" appears 1 time in a 9-word body → 1*1*1000/9 = 111 (integer division)
    const HTML = "<html><body><p>the quick brown fox jumped over the lazy dog</p></body></html>";
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, "quick", std.testing.allocator);
    defer data.deinit();
    try std.testing.expectEqual(@as(u32, 111), data.keyword_density);
    try std.testing.expectEqual(@as(usize, 9), data.total_words);
}

test "script and style content excluded from keyword extraction (mobile fixture)" {
    const HTML =
        \\<html><body>
        \\<script>var addeventlistener = document.querySelector(".swiper");</script>
        \\<style>.nav { color: hover; }</style>
        \\<p>Website audit reporting tool for professionals.</p>
        \\</body></html>
    ;
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, null, std.testing.allocator);
    defer data.deinit();
    for (data.top_keywords) |kf| {
        try std.testing.expect(!std.mem.eql(u8, kf.word, "addeventlistener"));
        try std.testing.expect(!std.mem.eql(u8, kf.word, "queryselector"));
        try std.testing.expect(!std.mem.eql(u8, kf.word, "var"));
        try std.testing.expect(!std.mem.eql(u8, kf.word, "nav"));
        try std.testing.expect(!std.mem.eql(u8, kf.word, "hover"));
    }
    try std.testing.expect(data.total_words > 0);
}

test "checkKeywords returns empty slice for no keywords (mobile fixture)" {
    const HTML = "<html><body><p>some content here for testing</p></body></html>";
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const coverages = try checkKeywords(doc, &.{}, std.testing.allocator);
    defer {
        for (coverages) |kc| kc.deinit();
        std.testing.allocator.free(coverages);
    }
    try std.testing.expectEqual(@as(usize, 0), coverages.len);
}

test "checkKeywords coverage_score 40 for keyword in title only (mobile fixture)" {
    const HTML =
        \\<html><head><title>Site Audit Tool</title></head>
        \\<body><p>Professional platform for technical website analysis checks.</p></body></html>
    ;
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const kws = [_][]const u8{"site audit tool"};
    const coverages = try checkKeywords(doc, &kws, std.testing.allocator);
    defer {
        for (coverages) |kc| kc.deinit();
        std.testing.allocator.free(coverages);
    }
    try std.testing.expectEqual(@as(usize, 1), coverages.len);
    try std.testing.expect(coverages[0].in_title);
    try std.testing.expect(!coverages[0].in_h1);
    try std.testing.expect(!coverages[0].in_description);
    try std.testing.expectEqual(@as(u8, 40), coverages[0].coverage_score);
}

test "checkKeywords detects title h1 and description (mobile fixture)" {
    const HTML =
        \\<html><head>
        \\<title>Site Audit Tool</title>
        \\<meta name="description" content="The best site audit tool for seo"/>
        \\</head><body>
        \\<h1>Site Audit Tool</h1>
        \\<p>Professional platform for technical website analysis.</p>
        \\</body></html>
    ;
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const kws = [_][]const u8{"site audit tool"};
    const coverages = try checkKeywords(doc, &kws, std.testing.allocator);
    defer {
        for (coverages) |kc| kc.deinit();
        std.testing.allocator.free(coverages);
    }
    try std.testing.expectEqual(@as(usize, 1), coverages.len);
    try std.testing.expect(coverages[0].in_title);
    try std.testing.expect(coverages[0].in_h1);
    try std.testing.expect(coverages[0].in_description);
    try std.testing.expectEqual(@as(u8, 85), coverages[0].coverage_score);
}

test "no target keyword gives zero density and no target fields (mobile fixture)" {
    const HTML = "<html><body><p>some page content here</p></body></html>";
    const doc = html.parse(HTML) orelse return error.ParseFailed;
    defer doc.deinit();
    const data = try extract(doc, null, std.testing.allocator);
    defer data.deinit();
    try std.testing.expectEqual(@as(u32, 0), data.keyword_density);
    try std.testing.expect(data.target_keyword == null);
    try std.testing.expect(!data.target_in_title);
    try std.testing.expect(!data.target_in_h1);
    try std.testing.expect(!data.target_in_description);
}
