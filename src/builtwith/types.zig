const std = @import("std");

pub const TechEntry = struct {
    name: []const u8,
    tag: []const u8,
    category: []const u8,
};

pub const BuiltWithData = struct {
    technologies: []TechEntry,
    allocator: std.mem.Allocator,

    pub fn deinit(self: BuiltWithData) void {
        for (self.technologies) |t| {
            self.allocator.free(t.name);
            self.allocator.free(t.tag);
            self.allocator.free(t.category);
        }
        self.allocator.free(self.technologies);
    }
};

// ── tests ─────────────────────────────────────────────────────────────────────

test "BuiltWithData fields accessible" {
    const allocator = std.testing.allocator;
    const techs = try allocator.alloc(TechEntry, 1);
    techs[0] = .{
        .name     = try allocator.dupe(u8, "React"),
        .tag      = try allocator.dupe(u8, "javascript-frameworks"),
        .category = try allocator.dupe(u8, "JavaScript Frameworks"),
    };
    const data = BuiltWithData{ .technologies = techs, .allocator = allocator };
    defer data.deinit();
    try std.testing.expectEqualStrings("React", data.technologies[0].name);
    try std.testing.expectEqual(@as(usize, 1), data.technologies.len);
}

test "BuiltWithData deinit frees all entries" {
    const allocator = std.testing.allocator;
    const techs = try allocator.alloc(TechEntry, 0);
    const data = BuiltWithData{ .technologies = techs, .allocator = allocator };
    data.deinit(); // must not leak
}
