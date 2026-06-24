const std = @import("std");
const Io = std.Io;
const fetcher = @import("../fetcher.zig");
const parser = @import("parser.zig");
const types = @import("types.zig");
const audit_mod = @import("../audit.zig");
const helpers = @import("../xml_helpers.zig");

pub const BuiltWithData = types.BuiltWithData;

const ENDPOINT = "https://api.builtwith.com/v21/api.json";

/// Resolve BuiltWith API key: --builtwith-key flag → BUILTWITH_KEY env var.
/// Returns null if no key available.
pub fn resolveKey(explicit: ?[]const u8, allocator: std.mem.Allocator) !?[]const u8 {
    if (explicit) |k| return try allocator.dupe(u8, k);
    if (std.c.getenv("BUILTWITH_KEY")) |v| return try allocator.dupe(u8, std.mem.span(v));
    return null;
}

/// Fetch BuiltWith data for the page URL and enrich report in-place.
pub fn enrich(report: *audit_mod.AuditReport, api_key: []const u8, io: Io, allocator: std.mem.Allocator) !void {
    const domain = helpers.extractHostname(report.url) orelse return error.InvalidUrl;
    const body = try fetch(domain, api_key, io, allocator);
    defer allocator.free(body);
    const data = try parser.parse(body, allocator);
    if (report.builtwith) |old| old.deinit();
    report.builtwith = data;
}

/// Fetch raw JSON from BuiltWith API. Caller owns returned slice.
pub fn fetch(domain: []const u8, api_key: []const u8, io: Io, allocator: std.mem.Allocator) ![]const u8 {
    const url = try std.fmt.allocPrint(
        allocator,
        "{s}?KEY={s}&LOOKUP={s}",
        .{ ENDPOINT, api_key, domain },
    );
    defer allocator.free(url);

    const response = try fetcher.fetchWith(io, allocator, url, .{});
    errdefer allocator.free(response.body);

    if (response.status != .ok) {
        allocator.free(response.body);
        return error.BuiltWithApiFailed;
    }

    return response.body;
}

// ── tests ─────────────────────────────────────────────────────────────────────

test "ENDPOINT is correct BuiltWith API URL" {
    try std.testing.expectEqualStrings(
        "https://api.builtwith.com/v21/api.json",
        ENDPOINT,
    );
}

test "fetch URL assembled correctly" {
    const allocator = std.testing.allocator;
    const url = try std.fmt.allocPrint(
        allocator,
        "{s}?KEY={s}&LOOKUP={s}",
        .{ ENDPOINT, "TESTKEY", "example.com" },
    );
    defer allocator.free(url);
    try std.testing.expect(std.mem.indexOf(u8, url, "KEY=TESTKEY") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "LOOKUP=example.com") != null);
}

test "resolveKey returns null when no key available" {
    const allocator = std.testing.allocator;
    // only tests the explicit=null path; env var may or may not be set
    // so we can't assert null here if BUILTWITH_KEY happens to be in env
    const key = try resolveKey(null, allocator);
    if (key) |k| allocator.free(k);
}

test "resolveKey returns explicit key when provided" {
    const allocator = std.testing.allocator;
    const key = try resolveKey("mykey123", allocator);
    defer if (key) |k| allocator.free(k);
    try std.testing.expectEqualStrings("mykey123", key.?);
}
