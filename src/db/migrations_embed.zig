const std = @import("std");
const migrate = @import("migrate.zig");

pub const all: []const migrate.Migration = &[_]migrate.Migration{
    .{ .version = "001", .sql = @embedFile("../migrations/001_create_users.sql") },
    .{ .version = "002", .sql = @embedFile("../migrations/002_create_refresh_tokens.sql") },
    .{ .version = "003", .sql = @embedFile("../migrations/003_create_oauth_accounts.sql") },
    .{ .version = "004", .sql = @embedFile("../migrations/004_create_email_tokens.sql") },
    .{ .version = "005", .sql = @embedFile("../migrations/005_create_mfa_backup_codes.sql") },
    .{ .version = "006", .sql = @embedFile("../migrations/006_create_organizations.sql") },
    .{ .version = "007", .sql = @embedFile("../migrations/007_create_audit_runs.sql") },
    .{ .version = "008", .sql = @embedFile("../migrations/008_create_projects.sql") },
};

test "migrations sorted and unique" {
    try std.testing.expect(migrate.isSorted(all));
    try std.testing.expect(migrate.noDuplicates(all));
}
