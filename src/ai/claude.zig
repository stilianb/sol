const std = @import("std");
const Io = std.Io;

const ENDPOINT = "https://api.anthropic.com/v1/messages";
const MODEL = "claude-haiku-4-5-20251001";
const VERSION = "2023-06-01";

const SYSTEM_PROMPT =
    "You are a website SEO and performance auditor. Given audit findings and scores, " ++
    "return a JSON array of up to 6 recommendations. Each item must be: " ++
    "{\"quadrant\":\"no_brainer\"|\"quick_win\"|\"growth_move\"|\"transformational\"," ++
    "\"title\":\"...\",\"detail\":\"...\",\"effort\":\"low\"|\"medium\"|\"high\"," ++
    "\"impact\":\"low\"|\"medium\"|\"high\"}. " ++
    "Respond with ONLY the JSON array, no markdown, no explanation.";

pub const Recommendation = struct {
    quadrant: []const u8,
    title: []const u8,
    detail: []const u8,
    effort: []const u8,
    impact: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: Recommendation) void {
        self.allocator.free(self.quadrant);
        self.allocator.free(self.title);
        self.allocator.free(self.detail);
        self.allocator.free(self.effort);
        self.allocator.free(self.impact);
    }
};

pub const RecommendationsResult = struct {
    items: []Recommendation,
    allocator: std.mem.Allocator,

    pub fn deinit(self: RecommendationsResult) void {
        for (self.items) |r| r.deinit();
        self.allocator.free(self.items);
    }
};

fn resolveApiKey(explicit: ?[]const u8) ?[]const u8 {
    if (explicit) |k| return k;
    const raw = std.c.getenv("ANTHROPIC_API_KEY") orelse return null;
    return std.mem.span(raw);
}

/// Generate recommendations from audit findings. api_key: pass null to read from env.
pub fn generate(
    findings_json: []const u8,
    scores_json: []const u8,
    url: []const u8,
    api_key: ?[]const u8,
    io: Io,
    allocator: std.mem.Allocator,
) !RecommendationsResult {
    const key = resolveApiKey(api_key) orelse return error.MissingApiKey;

    const user_msg = try std.fmt.allocPrint(allocator,
        "URL: {s}\nScores: {s}\nFindings: {s}",
        .{ url, scores_json, findings_json });
    defer allocator.free(user_msg);

    // escape for JSON string
    const user_msg_escaped = try jsonEscape(user_msg, allocator);
    defer allocator.free(user_msg_escaped);

    const request_body = try std.fmt.allocPrint(allocator,
        "{{\"model\":\"{s}\",\"max_tokens\":1024,\"system\":\"{s}\",\"messages\":[{{\"role\":\"user\",\"content\":\"{s}\"}}]}}",
        .{ MODEL, SYSTEM_PROMPT, user_msg_escaped });
    defer allocator.free(request_body);

    const auth_header = try std.fmt.allocPrint(allocator, "x-api-key: {s}", .{key});
    defer allocator.free(auth_header);

    const extra_headers = [_]std.http.Header{
        .{ .name = "x-api-key", .value = key },
        .{ .name = "anthropic-version", .value = VERSION },
        .{ .name = "content-type", .value = "application/json" },
    };

    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    const uri = std.Uri.parse(ENDPOINT) catch return error.InvalidFormat;
    var req = try client.request(.POST, uri, .{
        .extra_headers = &extra_headers,
        .headers = .{ .content_type = .{ .override = "application/json" } },
    });
    defer req.deinit();

    const body_mut = try allocator.dupe(u8, request_body);
    defer allocator.free(body_mut);
    try req.sendBodyComplete(body_mut);

    var head_buf: [8192]u8 = undefined;
    var response = try req.receiveHead(&head_buf);

    if (@intFromEnum(response.head.status) != 200) return error.ApiError;

    var body_writer: std.Io.Writer.Allocating = .init(allocator);
    errdefer body_writer.deinit();

    var transfer_buf: [64]u8 = undefined;
    var decompress: std.http.Decompress = undefined;
    const r = response.readerDecompressing(&transfer_buf, &decompress, &.{});
    _ = r.streamRemaining(&body_writer.writer) catch |err| switch (err) {
        error.ReadFailed => return response.bodyErr().?,
        else => |e| return e,
    };
    const body = try body_writer.toOwnedSlice();
    defer allocator.free(body);

    return parseResponse(body, allocator);
}

const RecommendationJson = struct {
    quadrant: []const u8,
    title: []const u8,
    detail: []const u8,
    effort: []const u8,
    impact: []const u8,
};

const MessageResponse = struct {
    content: []const struct { text: []const u8 },
};

fn parseResponse(body: []const u8, allocator: std.mem.Allocator) !RecommendationsResult {
    const parsed_msg = std.json.parseFromSlice(MessageResponse, allocator, body, .{ .ignore_unknown_fields = true }) catch {
        return error.ParseFailed;
    };
    defer parsed_msg.deinit();

    if (parsed_msg.value.content.len == 0) return error.EmptyResponse;
    const text = parsed_msg.value.content[0].text;

    const parsed_arr = std.json.parseFromSlice([]const RecommendationJson, allocator, text, .{ .ignore_unknown_fields = true }) catch {
        return error.ParseFailed;
    };
    defer parsed_arr.deinit();

    var list: std.ArrayList(Recommendation) = .empty;
    errdefer {
        for (list.items) |r| r.deinit();
        list.deinit(allocator);
    }

    for (parsed_arr.value) |item| {
        try list.append(allocator, Recommendation{
            .quadrant = try allocator.dupe(u8, item.quadrant),
            .title = try allocator.dupe(u8, item.title),
            .detail = try allocator.dupe(u8, item.detail),
            .effort = try allocator.dupe(u8, item.effort),
            .impact = try allocator.dupe(u8, item.impact),
            .allocator = allocator,
        });
    }
    return RecommendationsResult{
        .items = try list.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

fn jsonEscape(input: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    for (input) |c| {
        switch (c) {
            '"' => try out.appendSlice(allocator, "\\\""),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            else => try out.append(allocator, c),
        }
    }
    return out.toOwnedSlice(allocator);
}

test "Recommendation deinit" {
    const allocator = std.testing.allocator;
    const r = Recommendation{
        .quadrant = try allocator.dupe(u8, "quick_win"),
        .title = try allocator.dupe(u8, "Add alt text"),
        .detail = try allocator.dupe(u8, "Images lack alt attributes."),
        .effort = try allocator.dupe(u8, "low"),
        .impact = try allocator.dupe(u8, "medium"),
        .allocator = allocator,
    };
    r.deinit();
}

test "jsonEscape basic" {
    const allocator = std.testing.allocator;
    const out = try jsonEscape("hello \"world\"\nnewline", allocator);
    defer allocator.free(out);
    try std.testing.expectEqualStrings("hello \\\"world\\\"\\nnewline", out);
}
