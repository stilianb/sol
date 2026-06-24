const std = @import("std");
const types = @import("types.zig");

pub const BuiltWithData = types.BuiltWithData;
pub const TechEntry = types.TechEntry;

/// Parse a BuiltWith API v21 JSON response into a flat BuiltWithData.
/// Flattens Results[0].Result.Paths[*].Technologies[*] into a deduplicated list.
pub fn parse(json_body: []const u8, allocator: std.mem.Allocator) !BuiltWithData {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_body, .{});
    defer parsed.deinit();
    const root = parsed.value;

    var techs: std.ArrayList(TechEntry) = .empty;
    errdefer {
        for (techs.items) |t| {
            allocator.free(t.name);
            allocator.free(t.tag);
            allocator.free(t.category);
        }
        techs.deinit(allocator);
    }

    const results = (root.object.get("Results") orelse return .{
        .technologies = try allocator.alloc(TechEntry, 0),
        .allocator = allocator,
    }).array;

    if (results.items.len == 0) return .{
        .technologies = try allocator.alloc(TechEntry, 0),
        .allocator = allocator,
    };

    const result_obj = results.items[0].object.get("Result") orelse return .{
        .technologies = try allocator.alloc(TechEntry, 0),
        .allocator = allocator,
    };

    const paths = (result_obj.object.get("Paths") orelse return .{
        .technologies = try allocator.alloc(TechEntry, 0),
        .allocator = allocator,
    }).array;

    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    for (paths.items) |path| {
        const path_techs = (path.object.get("Technologies") orelse continue).array;
        for (path_techs.items) |tech| {
            const name_val = tech.object.get("Name") orelse continue;
            const name = name_val.string;
            if (seen.contains(name)) continue;
            try seen.put(name, {});

            const tag = if (tech.object.get("Tag")) |t| t.string else "";
            const category = blk: {
                const cats = tech.object.get("Categories") orelse break :blk "";
                if (cats.array.items.len == 0) break :blk "";
                break :blk (cats.array.items[0].object.get("Name") orelse break :blk "").string;
            };

            try techs.append(allocator, .{
                .name     = try allocator.dupe(u8, name),
                .tag      = try allocator.dupe(u8, tag),
                .category = try allocator.dupe(u8, category),
            });
        }
    }

    return .{
        .technologies = try techs.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

// ── tests ─────────────────────────────────────────────────────────────────────

const FIXTURE =
    \\{
    \\  "Results": [{
    \\    "Result": {
    \\      "Paths": [
    \\        {
    \\          "Technologies": [
    \\            {"Name":"React","Tag":"javascript-frameworks","Categories":[{"Name":"JavaScript Frameworks"}]},
    \\            {"Name":"Cloudflare","Tag":"cdn","Categories":[{"Name":"CDN"}]}
    \\          ]
    \\        },
    \\        {
    \\          "Technologies": [
    \\            {"Name":"React","Tag":"javascript-frameworks","Categories":[{"Name":"JavaScript Frameworks"}]},
    \\            {"Name":"Google Analytics","Tag":"analytics","Categories":[{"Name":"Analytics"}]}
    \\          ]
    \\        }
    \\      ]
    \\    }
    \\  }]
    \\}
;

test "parse extracts technologies from fixture" {
    const allocator = std.testing.allocator;
    const data = try parse(FIXTURE, allocator);
    defer data.deinit();
    try std.testing.expectEqual(@as(usize, 3), data.technologies.len);
}

test "parse deduplicates technologies across paths" {
    const allocator = std.testing.allocator;
    const data = try parse(FIXTURE, allocator);
    defer data.deinit();
    var react_count: usize = 0;
    for (data.technologies) |t| if (std.mem.eql(u8, t.name, "React")) { react_count += 1; };
    try std.testing.expectEqual(@as(usize, 1), react_count);
}

test "parse extracts tag and category" {
    const allocator = std.testing.allocator;
    const data = try parse(FIXTURE, allocator);
    defer data.deinit();
    var found = false;
    for (data.technologies) |t| {
        if (std.mem.eql(u8, t.name, "Cloudflare")) {
            try std.testing.expectEqualStrings("cdn", t.tag);
            try std.testing.expectEqualStrings("CDN", t.category);
            found = true;
        }
    }
    try std.testing.expect(found);
}

test "parse returns empty when Results array is empty" {
    const allocator = std.testing.allocator;
    const data = try parse("{\"Results\":[]}", allocator);
    defer data.deinit();
    try std.testing.expectEqual(@as(usize, 0), data.technologies.len);
}
