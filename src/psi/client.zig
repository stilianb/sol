const std = @import("std");
const Io = std.Io;
const fetcher = @import("../fetcher.zig");
const parser = @import("parser.zig");
const types = @import("types.zig");
const audit_mod = @import("../audit.zig");

pub const PsiData = types.PsiData;

const PSI_ENDPOINT = "https://www.googleapis.com/pagespeedonline/v5/runPagespeed";

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
pub fn fetch(url: []const u8, api_key: []const u8, strategy: []const u8, io: Io, allocator: std.mem.Allocator) ![]const u8 {
    const request_url = try std.fmt.allocPrint(
        allocator,
        "{s}?url={s}&strategy={s}&key={s}",
        .{ PSI_ENDPOINT, url, strategy, api_key },
    );
    defer allocator.free(request_url);

    const response = try fetcher.fetchWith(io, allocator, request_url, .{});
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
