const std = @import("std");
const Io = std.Io;
const sol = @import("sol");
const router = sol.server.router;
const sse = sol.server.sse;
const context = sol.server.context;
const auth_handlers = @import("auth_handlers.zig");
const project_handlers = @import("project_handlers.zig");
const recommendations_handler = @import("recommendations_handler.zig");

const audit_mod = sol.audit;
const pool_mod = sol.crawler.pool;
const scorer_mod = sol.auditor.scorer;
const audit_runs_q = sol.db.queries.audit_runs;

const desktop_profile: audit_mod.AuditProfile = .{ .profile = .desktop, .gpu_accelerated = true };

const cors_headers = [_]std.http.Header{
    .{ .name = "access-control-allow-origin", .value = "*" },
    .{ .name = "access-control-allow-methods", .value = "GET, POST, DELETE, OPTIONS" },
    .{ .name = "access-control-allow-headers", .value = "content-type, authorization" },
};

// ── dispatch ──────────────────────────────────────────────────────────────────

pub fn dispatch(
    request: *std.http.Server.Request,
    io: Io,
    allocator: std.mem.Allocator,
    ctx: context.AppCtx,
) !void {
    if (request.head.method == .OPTIONS) {
        try request.respond("", .{ .extra_headers = &cors_headers });
        return;
    }
    switch (router.matchRoute(request.head.target)) {
        .audit => try handleAudit(request, io, allocator, ctx),
        .crawl => try handleCrawl(request, io, allocator),
        .health => try request.respond("ok", .{ .extra_headers = &cors_headers }),
        .auth_register => try auth_handlers.handleRegister(request, io, allocator, ctx),
        .auth_login    => try auth_handlers.handleLogin(request, io, allocator, ctx),
        .auth_refresh  => try auth_handlers.handleRefresh(request, io, allocator, ctx),
        .auth_logout   => try auth_handlers.handleLogout(request, io, allocator, ctx),
        .user_me       => try auth_handlers.handleMe(request, io, allocator, ctx),
        .projects_list, .projects_create => try project_handlers.handleListOrCreate(request, io, allocator, ctx),
        .project_get, .project_delete => try project_handlers.handleGetOrDelete(request, io, allocator, ctx),
        .project_audit => try project_handlers.handleTriggerAudit(request, io, allocator, ctx),
        .audit_runs => try handleAuditRuns(request, allocator, ctx),
        .recommendations => try recommendations_handler.handle(request, io, allocator, ctx),
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
    ctx: context.AppCtx,
) !void {
    const params = router.parseAuditParams(request.head.target) catch {
        try request.respond("missing url parameter", .{
            .status = .bad_request,
            .extra_headers = &cors_headers,
        });
        return;
    };

    var url_buf: [2048]u8 = undefined;
    const url = router.percentDecodeInto(params.url, &url_buf);

    var single_kw_buf: [1][]const u8 = undefined;
    const goal_kws: []const []const u8 = if (params.keyword) |kw| blk: {
        single_kw_buf[0] = kw;
        break :blk single_kw_buf[0..1];
    } else &.{};
    const report = audit_mod.run(url, desktop_profile, goal_kws, io, allocator) catch |err| {
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

    // persist to DB best-effort
    if (ctx.has_db) {
        const sc = report.score_result.scores;
        var scores_buf: [256]u8 = undefined;
        const scores_json = std.fmt.bufPrint(&scores_buf,
            "{{\"performance\":{d},\"accessibility\":{d},\"best_practices\":{d},\"seo\":{d},\"gdpr\":{d},\"keyword\":{d},\"aeo\":{d}}}",
            .{ sc.performance, sc.accessibility, sc.best_practices, sc.seo, sc.gdpr, sc.keyword, sc.aeo },
        ) catch "";
        const run_id = audit_runs_q.store(ctx.pool, null, url, "desktop", scores_json, null, null, allocator) catch |err| blk: {
            std.debug.print("audit_runs store failed: {}\n", .{err});
            break :blk null;
        };
        if (run_id) |rid| allocator.free(rid);
    }

    const resp_headers = cors_headers ++ [_]std.http.Header{
        .{ .name = "content-type", .value = "application/json" },
    };
    try request.respond(json, .{ .extra_headers = &resp_headers });
}

// ── /api/runs ─────────────────────────────────────────────────────────────────

fn handleAuditRuns(
    request: *std.http.Server.Request,
    allocator: std.mem.Allocator,
    ctx: context.AppCtx,
) !void {
    const resp_headers = cors_headers ++ [_]std.http.Header{
        .{ .name = "content-type", .value = "application/json" },
    };

    if (!ctx.has_db) {
        try request.respond("{\"error\":\"no database\"}", .{
            .status = .service_unavailable,
            .extra_headers = &resp_headers,
        });
        return;
    }

    const target = request.head.target;
    const q_url = blk: {
        if (std.mem.indexOfScalar(u8, target, '?')) |qi| {
            const query = target[qi + 1 ..];
            var it = std.mem.splitScalar(u8, query, '&');
            while (it.next()) |pair| {
                const eq = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
                if (std.mem.eql(u8, pair[0..eq], "url")) break :blk pair[eq + 1 ..];
            }
        }
        break :blk @as(?[]const u8, null);
    };

    const url = q_url orelse {
        try request.respond("{\"error\":\"missing url\"}", .{
            .status = .bad_request,
            .extra_headers = &resp_headers,
        });
        return;
    };

    var url_buf: [2048]u8 = undefined;
    const decoded_url = router.percentDecodeInto(url, &url_buf);

    const runs = audit_runs_q.listByUrl(ctx.pool, decoded_url, allocator) catch {
        try request.respond("{\"error\":\"db error\"}", .{
            .status = .internal_server_error,
            .extra_headers = &resp_headers,
        });
        return;
    };
    defer {
        for (runs) |r| r.deinit();
        allocator.free(runs);
    }

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);
    try buf.appendSlice(allocator, "[");
    for (runs, 0..) |r, i| {
        if (i > 0) try buf.appendSlice(allocator, ",");
        const item = try std.fmt.allocPrint(allocator,
            "{{\"id\":\"{s}\",\"url\":\"{s}\",\"profile\":\"{s}\",\"ran_at_us\":{d},\"scores\":{s}}}",
            .{ r.id, r.url, r.profile, r.ran_at_us, r.scores_json });
        defer allocator.free(item);
        try buf.appendSlice(allocator, item);
    }
    try buf.appendSlice(allocator, "]");
    try request.respond(buf.items, .{ .extra_headers = &resp_headers });
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

    var url_buf: [2048]u8 = undefined;
    const url = router.percentDecodeInto(params.url, &url_buf);

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

    const reports = pool_mod.crawlWithPool(url, .{
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
