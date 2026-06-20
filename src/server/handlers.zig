const std = @import("std");
const Io = std.Io;
const sol = @import("sol");
const router = sol.server.router;
const sse = sol.server.sse;

const audit_mod = sol.audit;
const pool_mod = sol.crawler.pool;
const scorer_mod = sol.auditor.scorer;

const desktop_profile: audit_mod.AuditProfile = .{ .profile = .desktop, .gpu_accelerated = true };

const cors_headers = [_]std.http.Header{
    .{ .name = "access-control-allow-origin", .value = "*" },
    .{ .name = "access-control-allow-methods", .value = "GET, OPTIONS" },
};

// ── dispatch ──────────────────────────────────────────────────────────────────

pub fn dispatch(
    request: *std.http.Server.Request,
    io: Io,
    allocator: std.mem.Allocator,
) !void {
    switch (router.matchRoute(request.head.target)) {
        .audit => try handleAudit(request, io, allocator),
        .crawl => try handleCrawl(request, io, allocator),
        .health => try request.respond("ok", .{ .extra_headers = &cors_headers }),
        .not_found => try request.respond("not found", .{
            .status = .not_found,
            .extra_headers = &cors_headers,
        }),
    }
}

// ── /api/audit ────────────────────────────────────────────────────────────────

fn handleAudit(
    request: *std.http.Server.Request,
    io: Io,
    allocator: std.mem.Allocator,
) !void {
    const params = router.parseAuditParams(request.head.target) catch {
        try request.respond("missing url parameter", .{
            .status = .bad_request,
            .extra_headers = &cors_headers,
        });
        return;
    };

    var single_kw_buf: [1][]const u8 = undefined;
    const goal_kws: []const []const u8 = if (params.keyword) |kw| blk: {
        single_kw_buf[0] = kw;
        break :blk single_kw_buf[0..1];
    } else &.{};
    const report = audit_mod.run(params.url, desktop_profile, goal_kws, io, allocator) catch |err| {
        var msg_buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "audit failed: {}", .{err}) catch "audit failed";
        try request.respond(msg, .{
            .status = .internal_server_error,
            .extra_headers = &cors_headers,
        });
        return;
    };
    defer report.deinit();

    var json_buf: [128 * 1024]u8 = undefined;
    var json_w = std.Io.Writer.fixed(&json_buf);
    try audit_mod.renderJson(report, &json_w);
    const json = std.Io.Writer.buffered(&json_w);

    const resp_headers = cors_headers ++ [_]std.http.Header{
        .{ .name = "content-type", .value = "application/json" },
    };
    try request.respond(json, .{ .extra_headers = &resp_headers });
}

// ── /api/crawl (SSE) ──────────────────────────────────────────────────────────

const CrawlContext = struct {
    body: *std.http.BodyWriter,
    total_pages: usize = 0,
    total_findings: usize = 0,
    critical_count: usize = 0,
    warning_count: usize = 0,
    info_count: usize = 0,

    fn onProgress(ctx: ?*anyopaque, event: pool_mod.ProgressEvent) void {
        const self: *CrawlContext = @ptrCast(@alignCast(ctx.?));
        sse.writeProgressEvent(&self.body.writer, event) catch {};
        self.body.flush() catch {};
    }

    fn onPage(ctx: ?*anyopaque, report: *const audit_mod.AuditReport) void {
        const self: *CrawlContext = @ptrCast(@alignCast(ctx.?));
        sse.writePageEvent(&self.body.writer, .{
            .url = report.url,
            .http_status = @intFromEnum(report.status),
            .scores = report.score_result.scores,
            .finding_count = report.score_result.findings.len,
        }) catch {};
        self.body.flush() catch {};
        self.total_pages += 1;
        self.total_findings += report.score_result.findings.len;
        for (report.score_result.findings) |f| {
            switch (f.severity) {
                .critical => self.critical_count += 1,
                .warning => self.warning_count += 1,
                .info => self.info_count += 1,
            }
        }
    }
};

fn handleCrawl(
    request: *std.http.Server.Request,
    io: Io,
    allocator: std.mem.Allocator,
) !void {
    const params = router.parseCrawlParams(request.head.target) catch {
        try request.respond("missing url parameter", .{
            .status = .bad_request,
            .extra_headers = &cors_headers,
        });
        return;
    };

    const sse_headers = cors_headers ++ [_]std.http.Header{
        .{ .name = "content-type", .value = "text/event-stream" },
        .{ .name = "cache-control", .value = "no-cache" },
        .{ .name = "x-accel-buffering", .value = "no" },
    };

    var crawl_kw_buf: [1][]const u8 = undefined;
    const crawl_goal_kws: []const []const u8 = if (params.keyword) |kw| blk: {
        crawl_kw_buf[0] = kw;
        break :blk crawl_kw_buf[0..1];
    } else &.{};

    var body_buf: [8192]u8 = undefined;
    var body = try request.respondStreaming(&body_buf, .{
        .respond_options = .{ .extra_headers = &sse_headers },
    });

    var ctx: CrawlContext = .{ .body = &body };

    const reports = pool_mod.crawlWithPool(params.url, .{
        .runner_count = params.runners,
        .max_depth = params.depth,
        .audit_profile = desktop_profile,
        .goal_keywords = crawl_goal_kws,
        .on_progress = CrawlContext.onProgress,
        .on_page = CrawlContext.onPage,
        .callback_ctx = &ctx,
    }, io, allocator) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "crawl failed: {}", .{err}) catch "crawl failed";
        defer if (msg.ptr != "crawl failed".ptr) allocator.free(msg);
        var fail_event_buf: [256]u8 = undefined;
        const fail_event = std.fmt.bufPrint(
            &fail_event_buf,
            "event: error\ndata: {{\"message\":\"{s}\"}}\n\n",
            .{msg},
        ) catch "";
        body.writer.writeAll(fail_event) catch {};
        body.end() catch {};
        return;
    };
    defer {
        for (reports) |r| r.deinit();
        allocator.free(reports);
    }

    try sse.writeDoneEvent(&body.writer, .{
        .total_pages = ctx.total_pages,
        .total_findings = ctx.total_findings,
        .critical_count = ctx.critical_count,
        .warning_count = ctx.warning_count,
        .info_count = ctx.info_count,
    });
    try body.end();
}
