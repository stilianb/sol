const std = @import("std");
const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;
const Encoder = std.base64.url_safe_no_pad.Encoder;
const Decoder = std.base64.url_safe_no_pad.Decoder;

pub const Claims = struct {
    sub: []const u8,
    exp: i64,
    iat: i64,
};

// base64url({"alg":"HS256","typ":"JWT"}) — precomputed, stable
const HEADER_B64 = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9";

fn nowSec() i64 {
    var ts: std.c.timespec = .{ .sec = 0, .nsec = 0 };
    _ = std.c.clock_gettime(std.c.CLOCK.REALTIME, &ts);
    return @as(i64, ts.sec);
}

/// Sign a JWT. Returns allocated string — caller owns and must free.
pub fn sign(email: []const u8, secret: []const u8, ttl_seconds: i64, allocator: std.mem.Allocator) ![]const u8 {
    const now = nowSec();
    const exp = now + ttl_seconds;

    const payload_json = try std.fmt.allocPrint(
        allocator,
        "{{\"sub\":\"{s}\",\"exp\":{d},\"iat\":{d}}}",
        .{ email, exp, now },
    );
    defer allocator.free(payload_json);

    const payload_b64_len = Encoder.calcSize(payload_json.len);
    const payload_b64 = try allocator.alloc(u8, payload_b64_len);
    defer allocator.free(payload_b64);
    _ = Encoder.encode(payload_b64, payload_json);

    // signing input: header.payload
    const signing_input = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ HEADER_B64, payload_b64 });
    defer allocator.free(signing_input);

    var mac: [HmacSha256.mac_length]u8 = undefined;
    HmacSha256.create(&mac, signing_input, secret);

    const sig_b64_len = Encoder.calcSize(mac.len);
    const sig_b64 = try allocator.alloc(u8, sig_b64_len);
    defer allocator.free(sig_b64);
    _ = Encoder.encode(sig_b64, &mac);

    return std.fmt.allocPrint(allocator, "{s}.{s}.{s}", .{ HEADER_B64, payload_b64, sig_b64 });
}

pub const JwtError = error{ Expired, InvalidSignature, Malformed };

/// Verify a JWT. Returns Claims on success.
pub fn verify(token: []const u8, secret: []const u8, allocator: std.mem.Allocator) !Claims {
    // split into 3 parts
    var parts: [3][]const u8 = undefined;
    var it = std.mem.splitScalar(u8, token, '.');
    var i: usize = 0;
    while (it.next()) |p| {
        if (i >= 3) return JwtError.Malformed;
        parts[i] = p;
        i += 1;
    }
    if (i != 3) return JwtError.Malformed;

    // verify signature
    const signing_input = token[0 .. parts[0].len + 1 + parts[1].len];
    var mac: [HmacSha256.mac_length]u8 = undefined;
    HmacSha256.create(&mac, signing_input, secret);

    const expected_sig_len = Encoder.calcSize(mac.len);
    const expected_sig = try allocator.alloc(u8, expected_sig_len);
    defer allocator.free(expected_sig);
    _ = Encoder.encode(expected_sig, &mac);

    if (!std.mem.eql(u8, parts[2], expected_sig)) return JwtError.InvalidSignature;

    // decode payload
    const payload_decoded_len = try Decoder.calcSizeForSlice(parts[1]);
    const payload_decoded = try allocator.alloc(u8, payload_decoded_len);
    defer allocator.free(payload_decoded);
    try Decoder.decode(payload_decoded, parts[1]);

    // parse claims from JSON manually
    const sub = extractJsonStr(payload_decoded, "sub") orelse return JwtError.Malformed;
    const exp = extractJsonInt(payload_decoded, "exp") orelse return JwtError.Malformed;
    const iat = extractJsonInt(payload_decoded, "iat") orelse return JwtError.Malformed;

    const now = nowSec();
    if (exp < now) return JwtError.Expired;

    const sub_owned = try allocator.dupe(u8, sub);
    return Claims{ .sub = sub_owned, .exp = exp, .iat = iat };
}

fn extractJsonStr(json: []const u8, key: []const u8) ?[]const u8 {
    const search = std.fmt.allocPrint(std.heap.page_allocator, "\"{s}\":\"", .{key}) catch return null;
    defer std.heap.page_allocator.free(search);
    const start = std.mem.indexOf(u8, json, search) orelse return null;
    const val_start = start + search.len;
    const val_end = std.mem.indexOfScalarPos(u8, json, val_start, '"') orelse return null;
    return json[val_start..val_end];
}

fn extractJsonInt(json: []const u8, key: []const u8) ?i64 {
    const search = std.fmt.allocPrint(std.heap.page_allocator, "\"{s}\":", .{key}) catch return null;
    defer std.heap.page_allocator.free(search);
    const start = std.mem.indexOf(u8, json, search) orelse return null;
    var val_start = start + search.len;
    // skip whitespace
    while (val_start < json.len and json[val_start] == ' ') val_start += 1;
    var val_end = val_start;
    while (val_end < json.len and (json[val_end] == '-' or (json[val_end] >= '0' and json[val_end] <= '9'))) val_end += 1;
    return std.fmt.parseInt(i64, json[val_start..val_end], 10) catch null;
}

test "sign produces 3-part token" {
    const allocator = std.testing.allocator;
    const token = try sign("user@example.com", "secret", 900, allocator);
    defer allocator.free(token);
    var count: usize = 0;
    for (token) |c| {
        if (c == '.') count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), count);
}

test "verify returns correct sub" {
    const allocator = std.testing.allocator;
    const token = try sign("user@example.com", "mysecret", 900, allocator);
    defer allocator.free(token);
    const claims = try verify(token, "mysecret", allocator);
    defer allocator.free(claims.sub);
    try std.testing.expectEqualStrings("user@example.com", claims.sub);
}

test "verify tampered token returns InvalidSignature" {
    const allocator = std.testing.allocator;
    const token = try sign("user@example.com", "secret", 900, allocator);
    defer allocator.free(token);
    const err = verify(token, "wrongsecret", allocator);
    try std.testing.expectError(JwtError.InvalidSignature, err);
}

test "verify expired token returns Expired" {
    const allocator = std.testing.allocator;
    // ttl = -1 means already expired
    const token = try sign("user@example.com", "secret", -1, allocator);
    defer allocator.free(token);
    const err = verify(token, "secret", allocator);
    try std.testing.expectError(JwtError.Expired, err);
}
