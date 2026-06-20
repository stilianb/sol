const std = @import("std");
const c = @import("../xml.zig").c;
const h = @import("../xml_helpers.zig");
const html = @import("../parser/html.zig");

// ── types ─────────────────────────────────────────────────────────────────────

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

    const body_text = h.xpathText(d, "//body", allocator) orelse try allocator.dupe(u8, "");
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
        if (word.len == 0 or word.len > lower_buf.len) continue;
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
