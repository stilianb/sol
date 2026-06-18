const std = @import("std");
const Io = std.Io;
const sol = @import("sol");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 2) {
        std.debug.print("usage: sol <url>\n", .{});
        return;
    }

    var stdout_buf: [4096]u8 = undefined;
    var stdout_fw: Io.File.Writer = .init(.stdout(), io, &stdout_buf);
    const out = &stdout_fw.interface;

    const profile: sol.audit.AuditProfile = .{ .profile = .desktop, .gpu_accelerated = true };
    const report = try sol.audit.run(args[1], profile, io, gpa);
    defer report.deinit();

    try sol.audit.renderText(report, out);
    try out.flush();
}
