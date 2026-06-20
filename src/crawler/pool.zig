const std = @import("std");
const Io = std.Io;
const audit_mod = @import("../audit.zig");
const AuditReport = audit_mod.AuditReport;
const AuditProfile = audit_mod.AuditProfile;
const Frontier = @import("crawler.zig").Frontier;

// ── types ─────────────────────────────────────────────────────────────────────

pub const RunnerStatus = enum { idle, working, done };

/// Immutable snapshot of a runner's state — safe to pass to callbacks.
pub const RunnerSnapshot = struct {
    id: usize,
    status: RunnerStatus,
    current_url: []const u8,
    pages_done: usize,
    pages_failed: usize,
};

/// Fired at round start (all runners show .working) and round end (back to .idle/.done).
pub const ProgressEvent = struct {
    phase: Phase,
    runners: []const RunnerSnapshot,
    total_done: usize,
    total_queued: usize,

    pub const Phase = enum { round_start, round_end };
};

pub const ProgressFn = *const fn (event: ProgressEvent) void;

pub const PoolOptions = struct {
    runner_count: usize = 4,
    max_depth: usize = 3,
    audit_profile: AuditProfile,
    target_keyword: ?[]const u8 = null,
    on_progress: ?ProgressFn = null,
};

// ── internal ──────────────────────────────────────────────────────────────────

const MAX_RUNNERS = 16;

const Runner = struct {
    id: usize,
    status: RunnerStatus = .idle,
    current_url: []const u8 = "",
    pages_done: usize = 0,
    pages_failed: usize = 0,

    fn snapshot(self: Runner) RunnerSnapshot {
        return .{
            .id = self.id,
            .status = self.status,
            .current_url = self.current_url,
            .pages_done = self.pages_done,
            .pages_failed = self.pages_failed,
        };
    }
};

fn auditIntoSlot(
    url: []const u8,
    opts: PoolOptions,
    io: Io,
    allocator: std.mem.Allocator,
    slot: *?AuditReport,
) Io.Cancelable!void {
    slot.* = audit_mod.run(url, opts.audit_profile, opts.target_keyword, io, allocator) catch null;
}

fn snapshots(runners: []const Runner, buf: []RunnerSnapshot) []RunnerSnapshot {
    for (runners, 0..) |r, i| buf[i] = r.snapshot();
    return buf[0..runners.len];
}

fn notify(
    runners: []const Runner,
    opts: *const PoolOptions,
    phase: ProgressEvent.Phase,
    total_done: usize,
    total_queued: usize,
) void {
    const cb = opts.on_progress orelse return;
    var buf: [MAX_RUNNERS]RunnerSnapshot = undefined;
    cb(.{
        .phase = phase,
        .runners = snapshots(runners, &buf),
        .total_done = total_done,
        .total_queued = total_queued,
    });
}

// ── crawlWithPool ─────────────────────────────────────────────────────────────

/// Crawl `seed_url` with a persistent pool of `opts.runner_count` runners.
///
/// Each round fills up to runner_count slots from the frontier and dispatches
/// them concurrently via Io.Group. Progress events fire at round start (status
/// .working, URLs assigned) and round end (status .idle, counts updated).
pub fn crawlWithPool(
    seed_url: []const u8,
    opts: PoolOptions,
    io: Io,
    allocator: std.mem.Allocator,
) ![]AuditReport {
    const runner_count = @min(opts.runner_count, MAX_RUNNERS);

    var runners: [MAX_RUNNERS]Runner = undefined;
    for (0..runner_count) |i| runners[i] = .{ .id = i };
    const active_runners = runners[0..runner_count];

    var frontier = Frontier.init(allocator);
    defer frontier.deinit();
    _ = try frontier.push(seed_url, 0);

    var reports: std.ArrayList(AuditReport) = .empty;
    errdefer {
        for (reports.items) |r| r.deinit();
        reports.deinit(allocator);
    }

    var total_done: usize = 0;

    while (!frontier.isEmpty()) {
        // Fill runner slots from frontier.
        var batch_urls: [MAX_RUNNERS][]const u8 = undefined;
        var batch_depths: [MAX_RUNNERS]usize = undefined;
        var batch_len: usize = 0;

        while (batch_len < runner_count) {
            const item = frontier.pop() orelse break;
            batch_urls[batch_len] = item.url;
            batch_depths[batch_len] = item.depth;
            active_runners[batch_len].status = .working;
            active_runners[batch_len].current_url = item.url;
            batch_len += 1;
        }
        // Mark any unfilled slots as idle (frontier ran short).
        for (batch_len..runner_count) |i| {
            active_runners[i].status = .idle;
            active_runners[i].current_url = "";
        }
        if (batch_len == 0) break;

        notify(active_runners, &opts, .round_start, total_done, frontier.visited.count() + total_done);

        var slots: [MAX_RUNNERS]?AuditReport = .{null} ** MAX_RUNNERS;
        var group: Io.Group = .init;
        for (0..batch_len) |i| {
            group.async(io, auditIntoSlot, .{
                batch_urls[i],
                opts,
                io,
                allocator,
                &slots[i],
            });
        }
        try group.await(io);

        // Process results and update runner state.
        for (0..batch_len) |i| {
            active_runners[i].status = .idle;
            active_runners[i].current_url = "";

            if (slots[i]) |report| {
                if (batch_depths[i] < opts.max_depth) {
                    for (report.links) |link| {
                        if (link.is_internal) _ = frontier.push(link.href, batch_depths[i] + 1) catch {};
                    }
                    if (report.sitemap) |sm| {
                        for (sm.entries) |entry| {
                            _ = frontier.push(entry.loc, batch_depths[i] + 1) catch {};
                        }
                    }
                }
                try reports.append(allocator, report);
                active_runners[i].pages_done += 1;
                total_done += 1;
            } else {
                active_runners[i].pages_failed += 1;
            }
        }

        // Mark runners whose slots had no work as done if frontier is now empty.
        if (frontier.isEmpty()) {
            for (active_runners) |*r| {
                if (r.status == .idle) r.status = .done;
            }
        }

        notify(active_runners, &opts, .round_end, total_done, frontier.visited.count() + total_done);

        if (reports.items.len > 0) {
            const delay = reports.items[reports.items.len - 1].robots.crawl_delay_ms;
            if (delay > 0 and !frontier.isEmpty()) {
                const ns = delay * std.time.ns_per_ms;
                const ts: std.c.timespec = .{
                    .sec = @intCast(ns / std.time.ns_per_s),
                    .nsec = @intCast(ns % std.time.ns_per_s),
                };
                _ = std.c.nanosleep(&ts, null);
            }
        }
    }

    return reports.toOwnedSlice(allocator);
}

// ── tests ─────────────────────────────────────────────────────────────────────

test "crawlWithPool processes seed URL with single runner (mobile)" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const profile: AuditProfile = .{ .profile = .mobile, .gpu_accelerated = false };
    const results = try crawlWithPool("https://example.com", .{
        .runner_count = 1,
        .max_depth = 0,
        .audit_profile = profile,
    }, io, allocator);
    defer {
        for (results) |r| r.deinit();
        allocator.free(results);
    }
    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqualStrings("https://example.com", results[0].url);
}

test "crawlWithPool with multiple runners produces no duplicate URLs (mobile)" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const profile: AuditProfile = .{ .profile = .mobile, .gpu_accelerated = false };
    const results = try crawlWithPool("https://example.com", .{
        .runner_count = 4,
        .max_depth = 1,
        .audit_profile = profile,
    }, io, allocator);
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

test "crawlWithPool runner_count capped at MAX_RUNNERS" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const profile: AuditProfile = .{ .profile = .mobile, .gpu_accelerated = false };
    const results = try crawlWithPool("https://example.com", .{
        .runner_count = 999,
        .max_depth = 0,
        .audit_profile = profile,
    }, io, allocator);
    defer {
        for (results) |r| r.deinit();
        allocator.free(results);
    }
    try std.testing.expectEqual(@as(usize, 1), results.len);
}

test "crawlWithPool progress callback fires at round_start and round_end" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const profile: AuditProfile = .{ .profile = .mobile, .gpu_accelerated = false };

    const S = struct {
        var call_count: usize = 0;
        var saw_start: bool = false;
        var saw_end: bool = false;
        fn cb(event: ProgressEvent) void {
            call_count += 1;
            switch (event.phase) {
                .round_start => saw_start = true,
                .round_end => saw_end = true,
            }
        }
    };
    S.call_count = 0;
    S.saw_start = false;
    S.saw_end = false;

    const results = try crawlWithPool("https://example.com", .{
        .runner_count = 2,
        .max_depth = 0,
        .audit_profile = profile,
        .on_progress = S.cb,
    }, io, allocator);
    defer {
        for (results) |r| r.deinit();
        allocator.free(results);
    }
    try std.testing.expect(S.saw_start);
    try std.testing.expect(S.saw_end);
    try std.testing.expect(S.call_count >= 2);
}

test "runner snapshot shows working status during round_start event" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const profile: AuditProfile = .{ .profile = .mobile, .gpu_accelerated = false };

    const S = struct {
        var saw_working_runner: bool = false;
        fn cb(event: ProgressEvent) void {
            if (event.phase != .round_start) return;
            for (event.runners) |r| {
                if (r.status == .working and r.current_url.len > 0) {
                    saw_working_runner = true;
                }
            }
        }
    };
    S.saw_working_runner = false;

    const results = try crawlWithPool("https://example.com", .{
        .runner_count = 2,
        .max_depth = 0,
        .audit_profile = profile,
        .on_progress = S.cb,
    }, io, allocator);
    defer {
        for (results) |r| r.deinit();
        allocator.free(results);
    }
    try std.testing.expect(S.saw_working_runner);
}

test "runner snapshots track pages_done count" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const profile: AuditProfile = .{ .profile = .mobile, .gpu_accelerated = false };

    const S = struct {
        var final_done: usize = 0;
        fn cb(event: ProgressEvent) void {
            if (event.phase != .round_end) return;
            var total: usize = 0;
            for (event.runners) |r| total += r.pages_done;
            final_done = total;
        }
    };
    S.final_done = 0;

    const results = try crawlWithPool("https://example.com", .{
        .runner_count = 2,
        .max_depth = 0,
        .audit_profile = profile,
        .on_progress = S.cb,
    }, io, allocator);
    defer {
        for (results) |r| r.deinit();
        allocator.free(results);
    }
    try std.testing.expectEqual(results.len, S.final_done);
}
