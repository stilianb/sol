const std = @import("std");
const Io = std.Io;
const sol = @import("sol");
const context = sol.server.context;
const h = @import("http_helpers.zig");
const claude = sol.ai.claude;

const RequestBody = struct {
    url: []const u8,
    findings_json: []const u8,
    scores_json: []const u8,
};

pub fn handle(
    request: *std.http.Server.Request,
    io: Io,
    allocator: std.mem.Allocator,
    ctx: context.AppCtx,
) !void {
    _ = ctx;

    if (request.head.method != .POST) {
        try request.respond("method not allowed", .{
            .status = .method_not_allowed,
            .extra_headers = &h.json_cors_headers,
        });
        return;
    }

    // Check API key available
    const api_key = if (std.c.getenv("ANTHROPIC_API_KEY")) |raw|
        std.mem.span(raw)
    else {
        try request.respond("{\"error\":\"ANTHROPIC_API_KEY not set\"}", .{
            .status = .service_unavailable,
            .extra_headers = &h.json_cors_headers,
        });
        return;
    };

    var reader_buf: [512]u8 = undefined;
    var body_buf: [32768]u8 = undefined;
    const body = try h.readBody(request, &reader_buf, &body_buf);

    const parsed = std.json.parseFromSlice(RequestBody, allocator, body, .{}) catch {
        return h.respond400(request, "{\"error\":\"invalid json\"}");
    };
    defer parsed.deinit();

    const result = claude.generate(
        parsed.value.findings_json,
        parsed.value.scores_json,
        parsed.value.url,
        api_key,
        io,
        allocator,
    ) catch |err| {
        var msg_buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf,
            "{{\"error\":\"recommendations failed: {}\"}}",
            .{err}) catch "{\"error\":\"recommendations failed\"}";
        try request.respond(msg, .{
            .status = .internal_server_error,
            .extra_headers = &h.json_cors_headers,
        });
        return;
    };
    defer result.deinit();

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);
    try buf.appendSlice(allocator, "[");
    for (result.items, 0..) |r, i| {
        if (i > 0) try buf.appendSlice(allocator, ",");
        const item = try std.fmt.allocPrint(allocator,
            "{{\"quadrant\":\"{s}\",\"title\":\"{s}\",\"detail\":\"{s}\",\"effort\":\"{s}\",\"impact\":\"{s}\"}}",
            .{ r.quadrant, r.title, r.detail, r.effort, r.impact });
        defer allocator.free(item);
        try buf.appendSlice(allocator, item);
    }
    try buf.appendSlice(allocator, "]");
    try request.respond(buf.items, .{ .extra_headers = &h.json_cors_headers });
}
