const std = @import("std");
const Io = std.Io;
const sol = @import("sol");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 2) {
        std.debug.print("usage: sol <url> [--depth N] [--keyword PHRASE] [--json] [--publish-issues]\n", .{});
        return;
    }

    const url = args[1];
    var max_depth: usize = 0;
    var json_output: bool = false;
    var publish_issues: bool = false;
    var target_keyword: ?[]const u8 = null;

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--depth") and i + 1 < args.len) {
            max_depth = std.fmt.parseInt(usize, args[i + 1], 10) catch 0;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--keyword") and i + 1 < args.len) {
            target_keyword = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--json")) {
            json_output = true;
        } else if (std.mem.eql(u8, args[i], "--publish-issues")) {
            publish_issues = true;
        }
    }

    var stdout_buf: [4096]u8 = undefined;
    var stdout_fw: Io.File.Writer = .init(.stdout(), io, &stdout_buf);
    const out = &stdout_fw.interface;

    const profile: sol.audit.AuditProfile = .{ .profile = .desktop, .gpu_accelerated = true };

    if (max_depth == 0) {
        const report = try sol.audit.run(url, profile, target_keyword, io, gpa);
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
        const reports = try sol.crawler.crawler.crawl(url, .{ .max_depth = max_depth, .audit_profile = profile }, io, gpa);
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

    try out.flush();
}
