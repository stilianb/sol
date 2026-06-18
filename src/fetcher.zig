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
};

pub const FetchOptions = struct {
    profile_name: ?[]const u8 = null,
};

pub fn fetch(io: std.Io, allocator: std.mem.Allocator, url: []const u8) !Response {
    return fetchWith(io, allocator, url, .{});
}

pub fn fetchWith(io: std.Io, allocator: std.mem.Allocator, url: []const u8, opts: FetchOptions) !Response {
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    var body: std.Io.Writer.Allocating = .init(allocator);
    errdefer body.deinit();

    var ts0: std.c.timespec = .{ .sec = 0, .nsec = 0 };
    var ts1: std.c.timespec = .{ .sec = 0, .nsec = 0 };
    _ = std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts0);

    var ua_buf: [256]u8 = undefined;
    var extra_headers_storage: [1]std.http.Header = undefined;
    const extra_headers: []const std.http.Header = if (opts.profile_name) |p| blk: {
        extra_headers_storage[0] = .{
            .name = "User-Agent",
            .value = formatUserAgent(build_options.version, p, &ua_buf),
        };
        break :blk extra_headers_storage[0..1];
    } else &.{};

    const result = try client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &body.writer,
        .extra_headers = extra_headers,
    });
    _ = std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts1);
    const t0_ns: u64 = @as(u64, @bitCast(@as(i64, ts0.sec))) * std.time.ns_per_s +
        @as(u64, @bitCast(@as(i64, ts0.nsec)));
    const t1_ns: u64 = @as(u64, @bitCast(@as(i64, ts1.sec))) * std.time.ns_per_s +
        @as(u64, @bitCast(@as(i64, ts1.nsec)));
    const duration_ms: u64 = if (t1_ns >= t0_ns) (t1_ns - t0_ns) / std.time.ns_per_ms else 0;

    return .{
        .status = result.status,
        .body = try body.toOwnedSlice(),
        .duration_ms = duration_ms,
    };
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

test "fetch works over HTTPS" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const result = try fetch(io, allocator, "https://example.com");
    defer allocator.free(result.body);

    try std.testing.expectEqual(std.http.Status.ok, result.status);
}
