const std = @import("std");
const Sha256 = std.crypto.hash.sha2.Sha256;

pub const TOKEN_LEN = 32;

/// Generate a random refresh token. Returns hex-encoded string (64 chars).
/// Caller owns returned memory.
pub fn generate(io: std.Io, allocator: std.mem.Allocator) ![]const u8 {
    var raw: [TOKEN_LEN]u8 = undefined;
    std.Io.random(io, &raw);
    const hex = std.fmt.bytesToHex(raw, .lower);
    const out = try allocator.dupe(u8, &hex);
    return out;
}

/// SHA256-hash a refresh token for DB storage.
/// Returns lowercase hex string (64 chars). Caller owns.
pub fn hashToken(token: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    var digest: [Sha256.digest_length]u8 = undefined;
    Sha256.hash(token, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    const out = try allocator.dupe(u8, &hex);
    return out;
}

test "generate produces 64-char hex string" {
    const tok = try generate(std.testing.io, std.testing.allocator);
    defer std.testing.allocator.free(tok);
    try std.testing.expectEqual(@as(usize, 64), tok.len);
    for (tok) |c| {
        try std.testing.expect((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f'));
    }
}

test "hashToken is deterministic" {
    const h1 = try hashToken("sometoken", std.testing.allocator);
    defer std.testing.allocator.free(h1);
    const h2 = try hashToken("sometoken", std.testing.allocator);
    defer std.testing.allocator.free(h2);
    try std.testing.expectEqualStrings(h1, h2);
}

test "hashToken differs for different inputs" {
    const h1 = try hashToken("token1", std.testing.allocator);
    defer std.testing.allocator.free(h1);
    const h2 = try hashToken("token2", std.testing.allocator);
    defer std.testing.allocator.free(h2);
    try std.testing.expect(!std.mem.eql(u8, h1, h2));
}
