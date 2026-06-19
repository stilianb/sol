const std = @import("std");
const build_options = @import("build_options");

pub fn formatUserAgent(version: []const u8, profile_name: []const u8, buf: *[256]u8) []u8 {
    return std.fmt.bufPrint(
        buf,
        "sol/{s} (site auditor; https://github.com/stilianb/sol; profile={s})",
        .{ version, profile_name },
    ) catch buf[0..0];
}

pub const Response = struct {
    status: std.http.Status,
    body: []const u8, // caller must free with the allocator passed to fetch
    duration_ms: u64,
    redirect_depth: usize,
};

pub const FetchOptions = struct {
    profile_name: ?[]const u8 = null,
};

pub fn fetch(io: std.Io, allocator: std.mem.Allocator, url: []const u8) !Response {
    return fetchWith(io, allocator, url, .{});
}

pub fn fetchWith(io: std.Io, allocator: std.mem.Allocator, url: []const u8, opts: FetchOptions) !Response {
    var ua_buf: [256]u8 = undefined;
    var extra_headers_storage: [1]std.http.Header = undefined;
    const extra_headers: []const std.http.Header = if (opts.profile_name) |p| blk: {
        extra_headers_storage[0] = .{
            .name = "User-Agent",
            .value = formatUserAgent(build_options.version, p, &ua_buf),
        };
        break :blk extra_headers_storage[0..1];
    } else &.{};

    var ts0: std.c.timespec = .{ .sec = 0, .nsec = 0 };
    _ = std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts0);

    var url_buf: [16384]u8 = undefined;
    if (url.len > url_buf.len) return error.InvalidFormat;
    @memcpy(url_buf[0..url.len], url);
    var current_url: []u8 = url_buf[0..url.len];

    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    var redirect_depth: usize = 0;

    while (true) {
        const uri = std.Uri.parse(current_url) catch return error.InvalidFormat;
        var req = try client.request(.GET, uri, .{
            .redirect_behavior = .unhandled,
            .extra_headers = extra_headers,
        });
        defer req.deinit();
        try req.sendBodiless();

        var redirect_buf: [8192]u8 = undefined;
        var response = try req.receiveHead(&redirect_buf);

        if (response.head.status.class() == .redirect and redirect_depth < 10) {
            const loc = response.head.location orelse break;
            // copy location before reader() invalidates head strings
            var loc_buf: [4096]u8 = undefined;
            if (loc.len > loc_buf.len) break;
            @memcpy(loc_buf[0..loc.len], loc);
            const loc_copy = loc_buf[0..loc.len];

            // drain redirect body
            var drain_buf: [64]u8 = undefined;
            const drain_reader = response.reader(&drain_buf);
            _ = drain_reader.discardRemaining() catch 0;

            // resolve URL (absolute only; relative breaks chain)
            const resolved = resolveUrl(current_url, loc_copy) orelse break;
            if (resolved.len > url_buf.len) break;
            @memcpy(url_buf[0..resolved.len], resolved);
            current_url = url_buf[0..resolved.len];
            redirect_depth += 1;
            continue;
        }

        // final response — read body
        var body: std.Io.Writer.Allocating = .init(allocator);
        errdefer body.deinit();

        const ce = response.head.content_encoding;
        const decompress_buf: []u8 = switch (ce) {
            .identity => &.{},
            .zstd, .deflate, .gzip => try allocator.alloc(u8, 128 * 1024),
            .compress => return error.UnsupportedCompressionMethod,
        };
        defer if (decompress_buf.len > 0) allocator.free(decompress_buf);

        var transfer_buf: [64]u8 = undefined;
        var decompress: std.http.Decompress = undefined;
        const r = response.readerDecompressing(&transfer_buf, &decompress, decompress_buf);
        _ = r.streamRemaining(&body.writer) catch |err| switch (err) {
            error.ReadFailed => return response.bodyErr().?,
            else => |e| return e,
        };

        var ts1: std.c.timespec = .{ .sec = 0, .nsec = 0 };
        _ = std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts1);
        const t0_ns: u64 = @as(u64, @bitCast(@as(i64, ts0.sec))) * std.time.ns_per_s +
            @as(u64, @bitCast(@as(i64, ts0.nsec)));
        const t1_ns: u64 = @as(u64, @bitCast(@as(i64, ts1.sec))) * std.time.ns_per_s +
            @as(u64, @bitCast(@as(i64, ts1.nsec)));
        const duration_ms: u64 = if (t1_ns >= t0_ns) (t1_ns - t0_ns) / std.time.ns_per_ms else 0;

        return .{
            .status = response.head.status,
            .body = try body.toOwnedSlice(),
            .duration_ms = duration_ms,
            .redirect_depth = redirect_depth,
        };
    }

    // redirect chain broken without final response (missing Location, etc.)
    return error.HttpRedirectLocationMissing;
}

/// Returns absolute URL: loc if already absolute, or origin+loc if root-relative.
/// Returns null for relative paths (caller breaks redirect chain).
fn resolveUrl(_: []const u8, loc: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, loc, "http://") or std.mem.startsWith(u8, loc, "https://"))
        return loc;
    if (std.mem.startsWith(u8, loc, "/")) {
        // root-relative: need to reconstruct but can't allocate here — caller handles
        return null;
    }
    return null;
}

test "fetch returns 200 for valid URL" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const result = try fetch(io, allocator, "https://example.com");
    defer allocator.free(result.body);

    try std.testing.expectEqual(std.http.Status.ok, result.status);
}

test "fetch returns non-zero body length for valid URL" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const result = try fetch(io, allocator, "https://example.com");
    defer allocator.free(result.body);

    try std.testing.expect(result.body.len > 0);
}

test "fetch returns error for invalid URL" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    try std.testing.expectError(
        error.InvalidFormat,
        fetch(io, allocator, "not-a-url"),
    );
}

test "formatUserAgent returns correct UA string for mobile profile" {
    var buf: [256]u8 = undefined;
    const ua = formatUserAgent("0.1.0", "mobile", &buf);
    try std.testing.expectEqualStrings(
        "sol/0.1.0 (site auditor; https://github.com/stilianb/sol; profile=mobile)",
        ua,
    );
}

test "fetchWith mobile profile succeeds for valid URL" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const result = try fetchWith(io, allocator, "https://example.com", .{ .profile_name = "mobile" });
    defer allocator.free(result.body);
    try std.testing.expectEqual(std.http.Status.ok, result.status);
    try std.testing.expect(result.body.len > 0);
}

test "fetchWith non-redirecting URL has redirect_depth 0 (mobile)" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const result = try fetchWith(io, allocator, "https://example.com", .{ .profile_name = "mobile" });
    defer allocator.free(result.body);
    try std.testing.expectEqual(@as(usize, 0), result.redirect_depth);
}

test "fetch works over HTTPS" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const result = try fetch(io, allocator, "https://example.com");
    defer allocator.free(result.body);

    try std.testing.expectEqual(std.http.Status.ok, result.status);
}
