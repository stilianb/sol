const std = @import("std");
const argon2 = std.crypto.pwhash.argon2;

const HASH_BUF_LEN = 128;

/// Hash a password using argon2id. Returns allocated PHC string — caller must free.
pub fn hash(password: []const u8, io: std.Io, allocator: std.mem.Allocator) ![]const u8 {
    var buf: [HASH_BUF_LEN]u8 = undefined;
    const result = try argon2.strHash(password, .{
        .allocator = allocator,
        .params = argon2.Params.owasp_2id,
        .mode = .argon2id,
    }, &buf, io);
    return allocator.dupe(u8, result);
}

/// Verify password against argon2id PHC hash string.
/// Returns true if match, false if wrong password, error otherwise.
pub fn verify(hash_str: []const u8, password: []const u8, io: std.Io, allocator: std.mem.Allocator) !bool {
    argon2.strVerify(hash_str, password, .{ .allocator = allocator }, io) catch |err| {
        if (err == error.PasswordVerificationFailed) return false;
        return err;
    };
    return true;
}

test "hash output starts with $argon2" {
    const h = try hash("mypassword", std.testing.io, std.testing.allocator);
    defer std.testing.allocator.free(h);
    try std.testing.expect(std.mem.startsWith(u8, h, "$argon2"));
}

test "hash then verify returns true" {
    const h = try hash("correctpassword", std.testing.io, std.testing.allocator);
    defer std.testing.allocator.free(h);
    const ok = try verify(h, "correctpassword", std.testing.io, std.testing.allocator);
    try std.testing.expect(ok);
}

test "wrong password returns false" {
    const h = try hash("correctpassword", std.testing.io, std.testing.allocator);
    defer std.testing.allocator.free(h);
    const ok = try verify(h, "wrongpassword", std.testing.io, std.testing.allocator);
    try std.testing.expect(!ok);
}
