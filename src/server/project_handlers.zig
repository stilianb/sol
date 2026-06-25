const std = @import("std");
const Io = std.Io;
const sol = @import("sol");
const context = sol.server.context;
const router = sol.server.router;
const h = @import("http_helpers.zig");
const jwt_mod = sol.auth.jwt;
const users_q = sol.db.queries.users;
const projects_q = sol.db.queries.projects;
const audit_mod = sol.audit;

const desktop_profile: audit_mod.AuditProfile = .{ .profile = .desktop, .gpu_accelerated = true };

const CreateBody = struct {
    name: []const u8,
    primary_url: []const u8,
    competitor_urls: ?[]const []const u8 = null,
};

/// Verify JWT and return user_id (UUID text). Returns null + sends 401 on failure.
/// Caller owns returned string (heap-allocated).
fn requireUserId(
    request: *std.http.Server.Request,
    ctx: context.AppCtx,
    allocator: std.mem.Allocator,
) !?[]const u8 {
    const token = h.extractBearer(request) orelse {
        try h.respond401(request);
        return null;
    };
    const claims = jwt_mod.verify(token, ctx.jwt_secret, allocator) catch {
        try h.respond401(request);
        return null;
    };
    defer allocator.free(claims.sub);

    if (!ctx.has_db) {
        try h.respond500(request);
        return null;
    }

    const user = (users_q.findByEmail(ctx.pool, claims.sub, allocator) catch {
        try h.respond500(request);
        return null;
    }) orelse {
        try h.respond401(request);
        return null;
    };
    defer user.deinit();

    return allocator.dupe(u8, user.id) catch {
        try h.respond500(request);
        return null;
    };
}

pub fn handleListOrCreate(
    request: *std.http.Server.Request,
    io: Io,
    allocator: std.mem.Allocator,
    ctx: context.AppCtx,
) !void {
    _ = io;
    if (request.head.method == .GET) {
        return handleList(request, allocator, ctx);
    }
    if (request.head.method == .POST) {
        return handleCreate(request, allocator, ctx);
    }
    try request.respond("method not allowed", .{
        .status = .method_not_allowed,
        .extra_headers = &h.json_cors_headers,
    });
}

fn handleList(
    request: *std.http.Server.Request,
    allocator: std.mem.Allocator,
    ctx: context.AppCtx,
) !void {
    const user_id = (try requireUserId(request, ctx, allocator)) orelse return;
    defer allocator.free(user_id);

    const projects = projects_q.listByUser(ctx.pool, user_id, allocator) catch {
        return h.respond500(request);
    };
    defer {
        for (projects) |p| p.deinit();
        allocator.free(projects);
    }

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);
    try buf.appendSlice(allocator, "[");
    for (projects, 0..) |p, i| {
        if (i > 0) try buf.appendSlice(allocator, ",");
        const item = try std.fmt.allocPrint(allocator,
            "{{\"id\":\"{s}\",\"name\":\"{s}\",\"primary_url\":\"{s}\",\"status\":\"{s}\",\"archived\":{s}}}",
            .{ p.id, p.name, p.primary_url, p.status, if (p.archived) "true" else "false" });
        defer allocator.free(item);
        try buf.appendSlice(allocator, item);
    }
    try buf.appendSlice(allocator, "]");
    try request.respond(buf.items, .{ .extra_headers = &h.json_cors_headers });
}

fn handleCreate(
    request: *std.http.Server.Request,
    allocator: std.mem.Allocator,
    ctx: context.AppCtx,
) !void {
    const user_id = (try requireUserId(request, ctx, allocator)) orelse return;
    defer allocator.free(user_id);

    var reader_buf: [512]u8 = undefined;
    var body_buf: [8192]u8 = undefined;
    const body = try h.readBody(request, &reader_buf, &body_buf);

    const parsed = std.json.parseFromSlice(CreateBody, allocator, body, .{}) catch {
        return h.respond400(request, "{\"error\":\"invalid json\"}");
    };
    defer parsed.deinit();

    // Serialize competitor_urls to JSON
    var comp_buf: std.ArrayList(u8) = .empty;
    defer comp_buf.deinit(allocator);
    if (parsed.value.competitor_urls) |urls| {
        try comp_buf.appendSlice(allocator, "[");
        for (urls, 0..) |u, i| {
            if (i > 0) try comp_buf.appendSlice(allocator, ",");
            const item = try std.fmt.allocPrint(allocator, "\"{s}\"", .{u});
            defer allocator.free(item);
            try comp_buf.appendSlice(allocator, item);
        }
        try comp_buf.appendSlice(allocator, "]");
    } else {
        try comp_buf.appendSlice(allocator, "[]");
    }

    const project = projects_q.create(
        ctx.pool,
        parsed.value.name,
        parsed.value.primary_url,
        comp_buf.items,
        user_id,
        allocator,
    ) catch {
        return h.respond500(request);
    };
    defer project.deinit();

    var resp_buf: [1024]u8 = undefined;
    const resp = try std.fmt.bufPrint(&resp_buf,
        "{{\"id\":\"{s}\",\"name\":\"{s}\",\"primary_url\":\"{s}\",\"status\":\"{s}\"}}",
        .{ project.id, project.name, project.primary_url, project.status });
    try request.respond(resp, .{ .extra_headers = &h.json_cors_headers });
}

pub fn handleGetOrDelete(
    request: *std.http.Server.Request,
    io: Io,
    allocator: std.mem.Allocator,
    ctx: context.AppCtx,
) !void {
    _ = io;
    if (request.head.method == .GET) {
        return handleGet(request, allocator, ctx);
    }
    if (request.head.method == .DELETE) {
        return handleDelete(request, allocator, ctx);
    }
    try request.respond("method not allowed", .{
        .status = .method_not_allowed,
        .extra_headers = &h.json_cors_headers,
    });
}

fn handleGet(
    request: *std.http.Server.Request,
    allocator: std.mem.Allocator,
    ctx: context.AppCtx,
) !void {
    const user_id = (try requireUserId(request, ctx, allocator)) orelse return;
    defer allocator.free(user_id);

    const id = router.extractSegment(request.head.target, "/projects/") orelse {
        return h.respond400(request, "{\"error\":\"missing project id\"}");
    };

    const project = (projects_q.findById(ctx.pool, id, user_id, allocator) catch {
        return h.respond500(request);
    }) orelse {
        try request.respond("{\"error\":\"not found\"}", .{
            .status = .not_found,
            .extra_headers = &h.json_cors_headers,
        });
        return;
    };
    defer project.deinit();

    var resp_buf: [2048]u8 = undefined;
    const resp = try std.fmt.bufPrint(&resp_buf,
        "{{\"id\":\"{s}\",\"name\":\"{s}\",\"primary_url\":\"{s}\",\"competitor_urls\":{s},\"status\":\"{s}\",\"archived\":{s}}}",
        .{ project.id, project.name, project.primary_url, project.competitor_urls, project.status, if (project.archived) "true" else "false" });
    try request.respond(resp, .{ .extra_headers = &h.json_cors_headers });
}

fn handleDelete(
    request: *std.http.Server.Request,
    allocator: std.mem.Allocator,
    ctx: context.AppCtx,
) !void {
    const user_id = (try requireUserId(request, ctx, allocator)) orelse return;
    defer allocator.free(user_id);

    const id = router.extractSegment(request.head.target, "/projects/") orelse {
        return h.respond400(request, "{\"error\":\"missing project id\"}");
    };

    projects_q.archive(ctx.pool, id, user_id) catch {
        return h.respond500(request);
    };

    try request.respond("{}", .{ .extra_headers = &h.json_cors_headers });
}

pub fn handleTriggerAudit(
    request: *std.http.Server.Request,
    io: Io,
    allocator: std.mem.Allocator,
    ctx: context.AppCtx,
) !void {
    if (request.head.method != .POST) {
        try request.respond("method not allowed", .{
            .status = .method_not_allowed,
            .extra_headers = &h.json_cors_headers,
        });
        return;
    }

    const user_id = (try requireUserId(request, ctx, allocator)) orelse return;
    defer allocator.free(user_id);

    const id = router.extractSegment(request.head.target, "/projects/") orelse {
        return h.respond400(request, "{\"error\":\"missing project id\"}");
    };

    const project = (projects_q.findById(ctx.pool, id, user_id, allocator) catch {
        return h.respond500(request);
    }) orelse {
        try request.respond("{\"error\":\"not found\"}", .{
            .status = .not_found,
            .extra_headers = &h.json_cors_headers,
        });
        return;
    };
    defer project.deinit();

    const report = audit_mod.run(project.primary_url, desktop_profile, &.{}, io, allocator) catch |err| {
        var msg_buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "{{\"error\":\"audit failed: {}\"}}", .{err}) catch "{\"error\":\"audit failed\"}";
        try request.respond(msg, .{
            .status = .internal_server_error,
            .extra_headers = &h.json_cors_headers,
        });
        return;
    };
    defer report.deinit();

    var json_buf: [128 * 1024]u8 = undefined;
    var json_w = std.Io.Writer.fixed(&json_buf);
    try audit_mod.renderJson(report, &json_w);
    const json = std.Io.Writer.buffered(&json_w);
    try request.respond(json, .{ .extra_headers = &h.json_cors_headers });
}
