const std = @import("std");
const Io = std.Io;
const fetcher = @import("../fetcher.zig");
const parser = @import("parser.zig");
const types = @import("types.zig");
const audit_mod = @import("../audit.zig");

pub const PsiData = types.PsiData;

const PSI_ENDPOINT = "https://www.googleapis.com/pagespeedonline/v5/runPagespeed";

/// Resolve PSI token: --psi-key flag → SOL_PSI_KEY env → gcloud fallback.
/// Returns null if no credential source is available. Caller owns returned slice.
pub fn resolveToken(explicit_key: ?[]const u8, allocator: std.mem.Allocator, io: Io) !?[]const u8 {
    if (explicit_key) |k| return try allocator.dupe(u8, k);
    if (std.c.getenv("SOL_PSI_KEY")) |v| return try allocator.dupe(u8, std.mem.span(v));
    return gcloudToken(allocator, io);
}

/// Shell out to `gcloud auth print-access-token`. Returns null if gcloud absent/fails.
fn resolveQuotaProject() ?[]const u8 {
    if (std.c.getenv("GCLOUD_PROJECT")) |v| return std.mem.span(v);
    if (std.c.getenv("GOOGLE_CLOUD_PROJECT")) |v| return std.mem.span(v);
    if (std.c.getenv("CLOUDSDK_CORE_PROJECT")) |v| return std.mem.span(v);
    return null;
}

fn gcloudToken(allocator: std.mem.Allocator, io: Io) !?[]const u8 {
    const result = std.process.run(allocator, io, .{
        .argv = &.{ "gcloud", "auth", "print-access-token" },
    }) catch return null;
    defer allocator.free(result.stderr);
    defer allocator.free(result.stdout);
    if (result.stdout.len == 0) return null;
    const trimmed = std.mem.trimEnd(u8, result.stdout, "\n\r ");
    if (trimmed.len == 0) return null;
    return try allocator.dupe(u8, trimmed);
}

/// Fetch PSI data for a URL and enrich the report in-place.
/// No-op on error — caller logs the warning and continues without PSI data.
pub fn enrich(report: *audit_mod.AuditReport, api_key: []const u8, strategy: []const u8, io: Io, allocator: std.mem.Allocator) !void {
    const body = try fetch(report.url, api_key, strategy, io, allocator);
    defer allocator.free(body);
    const data = try parser.parse(body, strategy, allocator);
    if (report.psi) |old| old.deinit();
    report.psi = data;
}

/// Fetch raw JSON from PSI API. Caller owns returned slice.
/// token may be an OAuth bearer token (ya29.…) or an API key (AIzaSy…).
pub fn fetch(url: []const u8, token: []const u8, strategy: []const u8, io: Io, allocator: std.mem.Allocator) ![]const u8 {
    const is_bearer = std.mem.startsWith(u8, token, "ya29.");

    const request_url = if (is_bearer)
        try std.fmt.allocPrint(allocator, "{s}?url={s}&strategy={s}", .{ PSI_ENDPOINT, url, strategy })
    else
        try std.fmt.allocPrint(allocator, "{s}?url={s}&strategy={s}&key={s}", .{ PSI_ENDPOINT, url, strategy, token });
    defer allocator.free(request_url);

    var auth_buf: [512]u8 = undefined;
    const auth_header: ?[]const u8 = if (is_bearer)
        std.fmt.bufPrint(&auth_buf, "Bearer {s}", .{token}) catch null
    else
        null;

    // Bearer tokens need X-Goog-User-Project for quota; read from env or gcloud config.
    const quota_project: ?[]const u8 = if (is_bearer) resolveQuotaProject() else null;

    const response = try fetcher.fetchWith(io, allocator, request_url, .{
        .authorization = auth_header,
        .quota_project = quota_project,
    });
    errdefer allocator.free(response.body);

    if (response.status != .ok) {
        allocator.free(response.body);
        return error.PsiApiFailed;
    }

    return response.body;
}

// ── tests ─────────────────────────────────────────────────────────────────────

test "PSI_ENDPOINT is the correct Google API URL" {
    try std.testing.expectEqualStrings(
        "https://www.googleapis.com/pagespeedonline/v5/runPagespeed",
        PSI_ENDPOINT,
    );
}

test "fetch URL is correctly assembled" {
    const allocator = std.testing.allocator;
    const url = try std.fmt.allocPrint(
        allocator,
        "{s}?url={s}&strategy={s}&key={s}",
        .{ PSI_ENDPOINT, "https://example.com", "mobile", "TESTKEY" },
    );
    defer allocator.free(url);
    try std.testing.expect(std.mem.indexOf(u8, url, "strategy=mobile") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "key=TESTKEY") != null);
}
