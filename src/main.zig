const std = @import("std");
const Io = std.Io;
const sol = @import("sol");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 2) {
        std.debug.print("usage: sol <url> [--depth N]\n", .{});
        return;
    }

    const url = args[1];
    var max_depth: usize = 0;

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--depth") and i + 1 < args.len) {
            max_depth = std.fmt.parseInt(usize, args[i + 1], 10) catch 0;
            i += 1;
        }
    }

    var stdout_buf: [4096]u8 = undefined;
    var stdout_fw: Io.File.Writer = .init(.stdout(), io, &stdout_buf);
    const out = &stdout_fw.interface;

    const profile: sol.audit.AuditProfile = .{ .profile = .desktop, .gpu_accelerated = true };

    if (max_depth == 0) {
        const report = try sol.audit.run(url, profile, io, gpa);
        defer report.deinit();
        try sol.audit.renderText(report, out);
    } else {
        const reports = try sol.crawler.crawler.crawl(url, .{ .max_depth = max_depth, .audit_profile = profile }, io, gpa);
        defer {
            for (reports) |r| r.deinit();
            gpa.free(reports);
        }
        for (reports) |report| {
            try sol.audit.renderText(report, out);
            try out.print("\n", .{});
        }
    }

    try out.flush();
}
