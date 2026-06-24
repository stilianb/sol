const std = @import("std");
const audit = @import("../audit.zig");

test "run stores mobile profile in report" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const profile: audit.AuditProfile = .{ .profile = .mobile, .gpu_accelerated = false };
    const report = try audit.run("https://example.com", profile, &.{}, io, allocator);
    defer report.deinit();
    try std.testing.expectEqual(audit.DeviceProfile.mobile, report.audit_profile.profile);
    try std.testing.expect(!report.audit_profile.gpu_accelerated);
}
