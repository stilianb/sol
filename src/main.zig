const std = @import("std");
const Io = std.Io;
const sol = @import("sol");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 2) {
        std.debug.print(
            "usage: sol <url> [url2 url3 ...] [--keyword PHRASE]... [--depth N] [--json] [--csv]\n" ++
                "       sol [--baseline FILE] [--compare FILE]\n" ++
                "       sol --goals [FILE]\n" ++
                "       2+ urls: competitive comparison mode\n",
            .{},
        );
        return;
    }

    var urls: std.ArrayList([]const u8) = .empty;
    var goals_file: ?[]const u8 = null;
    var goals_requested: bool = false;
    var max_depth: usize = 0;
    var json_output: bool = false;
    var csv_output: bool = false;
    var baseline_file: ?[]const u8 = null;
    var compare_file: ?[]const u8 = null;
    var psi_key: ?[]const u8 = null;
    var goal_keywords: std.ArrayList([]const u8) = .empty;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--goals")) {
            goals_requested = true;
            if (i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], "--")) {
                goals_file = args[i + 1];
                i += 1;
            } else {
                goals_file = "";
            }
        } else if (std.mem.eql(u8, arg, "--depth") and i + 1 < args.len) {
            max_depth = std.fmt.parseInt(usize, args[i + 1], 10) catch 0;
            i += 1;
        } else if (std.mem.eql(u8, arg, "--keyword") and i + 1 < args.len) {
            try goal_keywords.append(arena, args[i + 1]);
            i += 1;
        } else if (std.mem.eql(u8, arg, "--json")) {
            json_output = true;
        } else if (std.mem.eql(u8, arg, "--csv")) {
            csv_output = true;
        } else if (std.mem.eql(u8, arg, "--baseline") and i + 1 < args.len) {
            baseline_file = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--compare") and i + 1 < args.len) {
            compare_file = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--psi-key") and i + 1 < args.len) {
            psi_key = args[i + 1];
            i += 1;
        } else if (!std.mem.startsWith(u8, arg, "--")) {
            try urls.append(arena, arg);
        }
    }

    const url: ?[]const u8 = if (urls.items.len == 1) urls.items[0] else null;

    var stdout_buf: [4096]u8 = undefined;
    var stdout_fw: Io.File.Writer = .init(.stdout(), io, &stdout_buf);
    const out = &stdout_fw.interface;

    const profile: sol.audit.AuditProfile = .{ .profile = .desktop, .gpu_accelerated = true };
    const kw_slice: []const []const u8 = goal_keywords.items;

    if (goals_requested) {
        const goals = blk: {
            const path = goals_file orelse "";
            if (path.len > 0) {
                break :blk sol.goals.goals.load(path, io, gpa) catch |err| {
                    if (err == error.FileNotFound) {
                        std.debug.print("error: goals file not found: {s}\n", .{path});
                        return;
                    }
                    return err;
                };
            } else {
                const maybe = try sol.goals.goals.discover(io, gpa);
                if (maybe == null) {
                    std.debug.print(
                        "error: sol-goals.json not found in current directory. use --goals FILE to specify a path.\n",
                        .{},
                    );
                    return;
                }
                break :blk maybe.?;
            }
        };
        defer goals.deinit();

        const goals_report = try sol.goals.tracker.run(goals, profile, io, gpa);
        defer goals_report.deinit();

        try sol.goals.tracker.renderJson(goals_report, out);
    } else if (urls.items.len >= 2) {
        var reports = try gpa.alloc(sol.audit.AuditReport, urls.items.len);
        var audited: usize = 0;
        defer {
            for (reports[0..audited]) |r| r.deinit();
            gpa.free(reports);
        }
        for (urls.items) |u| {
            reports[audited] = try sol.audit.run(u, profile, kw_slice, io, gpa);
            audited += 1;
        }
        var entries = try gpa.alloc(sol.audit.CompareEntry, audited);
        defer gpa.free(entries);
        for (reports[0..audited], 0..) |r, idx| {
            entries[idx] = .{
                .url = r.url,
                .scores = r.score_result.scores,
                .findings = r.score_result.findings,
            };
        }
        for (reports[0..audited]) |report| {
            try sol.audit.renderSummary(report, out);
            try out.print("\n", .{});
        }
        try sol.audit.renderCompare(entries, out);
    } else if (url) |u| {
        if (max_depth == 0) {
            var report = try sol.audit.run(u, profile, kw_slice, io, gpa);
            defer report.deinit();

            if (psi_key) |key| {
                sol.psi.client.enrich(&report, key, "mobile", io, gpa) catch |err| {
                    std.debug.print("warning: PSI fetch failed: {}\n", .{err});
                };
            }

            if (baseline_file) |bf| {
                const cwd = std.Io.Dir.cwd();
                const io_file = try cwd.createFile(io, bf, .{});
                defer io_file.close(io);
                var file_buf: [4096]u8 = undefined;
                var file_fw: Io.File.Writer = .init(io_file, io, &file_buf);
                try sol.audit.renderJson(report, &file_fw.interface);
                try file_fw.interface.flush();
                try out.print("baseline written to {s}\n", .{bf});
            } else if (compare_file) |cf| {
                const baseline_text = try std.Io.Dir.cwd().readFileAlloc(io, cf, gpa, .unlimited);
                defer gpa.free(baseline_text);
                const base_page = try sol.baseline.parseBaselinePage(baseline_text, gpa);
                defer base_page.deinit();
                const page_diff = try sol.baseline.diffPage(report, base_page, gpa);
                defer page_diff.deinit();
                const diff_result = sol.baseline.DiffResult{ .pages = @constCast(&[_]sol.baseline.PageDiff{page_diff}), .allocator = gpa };
                try sol.baseline.renderDiff(diff_result, out);
            } else if (json_output) {
                try sol.audit.renderJson(report, out);
            } else if (csv_output) {
                try sol.audit.renderCsv(&.{report}, out);
            } else {
                try sol.audit.renderText(report, out);
                try sol.audit.renderSummary(report, out);
            }
        } else {
            const reports = try sol.crawler.crawler.crawl(u, .{
                .max_depth = max_depth,
                .audit_profile = profile,
                .goal_keywords = kw_slice,
            }, io, gpa);
            defer {
                for (reports) |r| r.deinit();
                gpa.free(reports);
            }
            if (csv_output) {
                try sol.audit.renderCsv(reports, out);
            }
            for (reports) |report| {
                if (csv_output) {
                    // already emitted above
                } else if (json_output) {
                    try sol.audit.renderJson(report, out);
                } else {
                    try sol.audit.renderText(report, out);
                    try sol.audit.renderSummary(report, out);
                    try out.print("\n", .{});
                }
            }
        }
    } else {
        std.debug.print(
            "usage: sol <url> [url2 url3 ...] [--keyword PHRASE]... [--depth N] [--json] [--csv]\n" ++
                "       sol [--baseline FILE] [--compare FILE] [--psi-key KEY]\n" ++
                "       sol --goals [FILE]\n" ++
                "       2+ urls: competitive comparison mode\n",
            .{},
        );
    }

    try out.flush();
}
