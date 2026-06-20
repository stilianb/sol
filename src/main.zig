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
            "usage: sol <url> [--keyword PHRASE]... [--depth N] [--json] [--publish-issues]\n" ++
                "       sol --goals [FILE]\n",
            .{},
        );
        return;
    }

    var url: ?[]const u8 = null;
    var goals_file: ?[]const u8 = null; // "" = auto-discover; other = explicit path
    var goals_requested: bool = false;
    var max_depth: usize = 0;
    var json_output: bool = false;
    var publish_issues: bool = false;
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
        } else if (std.mem.eql(u8, arg, "--publish-issues")) {
            publish_issues = true;
        } else if (!std.mem.startsWith(u8, arg, "--")) {
            url = arg;
        }
    }

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
    } else if (url) |u| {
        if (max_depth == 0) {
            const report = try sol.audit.run(u, profile, kw_slice, io, gpa);
            defer report.deinit();
            if (json_output) {
                try sol.audit.renderJson(report, out);
            } else {
                try sol.audit.renderText(report, out);
                try sol.audit.renderSummary(report, out);
            }
            if (publish_issues) {
                const records = try sol.reporter.issueRecordsFrom(
                    report.url,
                    report.score_result.findings,
                    gpa,
                );
                defer gpa.free(records);
                try sol.reporter.publishIssues(records, io, gpa);
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
            for (reports) |report| {
                if (json_output) {
                    try sol.audit.renderJson(report, out);
                } else {
                    try sol.audit.renderText(report, out);
                    try sol.audit.renderSummary(report, out);
                    try out.print("\n", .{});
                }
                if (publish_issues) {
                    const records = try sol.reporter.issueRecordsFrom(
                        report.url,
                        report.score_result.findings,
                        gpa,
                    );
                    defer gpa.free(records);
                    try sol.reporter.publishIssues(records, io, gpa);
                }
            }
        }
    } else {
        std.debug.print(
            "usage: sol <url> [--keyword PHRASE]... [--depth N] [--json] [--publish-issues]\n" ++
                "       sol --goals [FILE]\n",
            .{},
        );
    }

    try out.flush();
}
