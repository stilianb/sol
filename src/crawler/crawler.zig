const std = @import("std");
const Io = std.Io;
const audit_mod = @import("../audit.zig");
const AuditProfile = audit_mod.AuditProfile;
const AuditReport = audit_mod.AuditReport;
const helpers = @import("../xml_helpers.zig");
const robots_mod = @import("robots.zig");
const fetcher = @import("../fetcher.zig");

// ── Frontier ──────────────────────────────────────────────────────────────────

const PendingUrl = struct {
    url: []const u8,
    depth: usize,
};

pub const Frontier = struct {
    visited: std.StringHashMap(void),
    pending: std.ArrayList(PendingUrl),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Frontier {
        return .{
            .visited = std.StringHashMap(void).init(allocator),
            .pending = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Frontier) void {
        var it = self.visited.keyIterator();
        while (it.next()) |k| self.allocator.free(k.*);
        self.visited.deinit();
        // pending items share ownership with visited keys — no double-free needed
        self.pending.deinit(self.allocator);
    }

    /// Returns true if url was new and added to the pending queue.
    pub fn push(self: *Frontier, url: []const u8, depth: usize) !bool {
        if (self.visited.contains(url)) return false;
        const owned = try self.allocator.dupe(u8, url);
        try self.visited.put(owned, {});
        try self.pending.append(self.allocator, .{ .url = owned, .depth = depth });
        return true;
    }

    pub fn pop(self: *Frontier) ?PendingUrl {
        if (self.pending.items.len == 0) return null;
        return self.pending.orderedRemove(0);
    }

    pub fn isEmpty(self: *const Frontier) bool {
        return self.pending.items.len == 0;
    }
};

// ── crawl ─────────────────────────────────────────────────────────────────────

pub const CrawlOptions = struct {
    max_depth: usize = 3,
    audit_profile: AuditProfile,
};

const BATCH_SIZE = 4;

fn auditIntoSlot(
    url: []const u8,
    profile: AuditProfile,
    io: Io,
    allocator: std.mem.Allocator,
    slot: *?AuditReport,
) Io.Cancelable!void {
    slot.* = audit_mod.run(url, profile, null, io, allocator) catch null;
}

pub fn crawl(
    seed_url: []const u8,
    opts: CrawlOptions,
    io: Io,
    allocator: std.mem.Allocator,
) ![]AuditReport {
    var frontier = Frontier.init(allocator);
    defer frontier.deinit();

    var reports: std.ArrayList(AuditReport) = .empty;
    errdefer {
        for (reports.items) |r| r.deinit();
        reports.deinit(allocator);
    }

    _ = try frontier.push(seed_url, 0);

    while (!frontier.isEmpty()) {
        var batch: [BATCH_SIZE]PendingUrl = undefined;
        var batch_len: usize = 0;
        while (batch_len < BATCH_SIZE) {
            const item = frontier.pop() orelse break;
            batch[batch_len] = item;
            batch_len += 1;
        }
        if (batch_len == 0) break;

        var slots: [BATCH_SIZE]?AuditReport = .{null} ** BATCH_SIZE;
        var group: Io.Group = .init;
        for (batch[0..batch_len], 0..) |item, i| {
            group.async(io, auditIntoSlot, .{
                item.url,
                opts.audit_profile,
                io,
                allocator,
                &slots[i],
            });
        }
        try group.await(io);

        var delay_ms: u64 = 0;

        for (slots[0..batch_len], 0..) |maybe_report, i| {
            const report = maybe_report orelse continue;
            if (delay_ms == 0) delay_ms = report.robots.crawl_delay_ms;

            const current_depth = batch[i].depth;

            if (current_depth < opts.max_depth) {
                for (report.links) |link| {
                    if (link.is_internal) {
                        _ = frontier.push(link.href, current_depth + 1) catch {};
                    }
                }
                if (report.sitemap) |sm| {
                    for (sm.entries) |entry| {
                        _ = frontier.push(entry.loc, current_depth + 1) catch {};
                    }
                }
            }

            try reports.append(allocator, report);
        }

        if (delay_ms > 0 and !frontier.isEmpty()) {
            const ns = delay_ms * std.time.ns_per_ms;
            const ts: std.c.timespec = .{ .sec = @intCast(ns / std.time.ns_per_s), .nsec = @intCast(ns % std.time.ns_per_s) };
            _ = std.c.nanosleep(&ts, null);
        }
    }

    return reports.toOwnedSlice(allocator);
}

// ── tests ─────────────────────────────────────────────────────────────────────

test "Frontier push new URL returns true" {
    var f = Frontier.init(std.testing.allocator);
    defer f.deinit();
    const added = try f.push("https://example.com/", 0);
    try std.testing.expect(added);
}

test "Frontier push duplicate returns false" {
    var f = Frontier.init(std.testing.allocator);
    defer f.deinit();
    _ = try f.push("https://example.com/", 0);
    const added = try f.push("https://example.com/", 0);
    try std.testing.expect(!added);
}

test "Frontier pop returns FIFO order" {
    var f = Frontier.init(std.testing.allocator);
    defer f.deinit();
    _ = try f.push("https://example.com/a", 0);
    _ = try f.push("https://example.com/b", 0);
    const first = f.pop().?;
    try std.testing.expectEqualStrings("https://example.com/a", first.url);
    const second = f.pop().?;
    try std.testing.expectEqualStrings("https://example.com/b", second.url);
}

test "Frontier pop empty returns null" {
    var f = Frontier.init(std.testing.allocator);
    defer f.deinit();
    try std.testing.expect(f.pop() == null);
}

test "crawl max_depth=0 returns only seed report (mobile)" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const profile: AuditProfile = .{ .profile = .mobile, .gpu_accelerated = false };
    const results = try crawl("https://example.com", .{ .max_depth = 0, .audit_profile = profile }, io, allocator);
    defer {
        for (results) |r| r.deinit();
        allocator.free(results);
    }
    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqualStrings("https://example.com", results[0].url);
}

test "crawl results have no duplicate URLs (mobile)" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const profile: AuditProfile = .{ .profile = .mobile, .gpu_accelerated = false };
    const results = try crawl("https://example.com", .{ .max_depth = 1, .audit_profile = profile }, io, allocator);
    defer {
        for (results) |r| r.deinit();
        allocator.free(results);
    }
    for (results, 0..) |a, i| {
        for (results[i + 1 ..]) |b| {
            try std.testing.expect(!std.mem.eql(u8, a.url, b.url));
        }
    }
}
