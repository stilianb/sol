const std = @import("std");
const Io = std.Io;
const sol = @import("sol");
const context = sol.server.context;

fn nowMicroSec() i64 {
    var ts: std.c.timespec = .{ .sec = 0, .nsec = 0 };
    _ = std.c.clock_gettime(std.c.CLOCK.REALTIME, &ts);
    return @as(i64, ts.sec) * 1_000_000 + @divTrunc(@as(i64, ts.nsec), 1000);
}
const h = @import("http_helpers.zig");
const jwt_mod = sol.auth.jwt;
const password_mod = sol.auth.password;
const tokens_mod = sol.auth.tokens;
const users_q = sol.db.queries.users;
const toks_q = sol.db.queries.tokens;

const REFRESH_TTL_US: i64 = 30 * 24 * 60 * 60 * 1_000_000;
const JWT_TTL_S: i64 = 900;

const LoginBody = struct { email: []const u8, password: []const u8 };
const RefreshBody = struct { refresh_token: []const u8 };
const LogoutBody = struct { refresh_token: []const u8 };

pub fn handleRegister(
    request: *std.http.Server.Request,
    io: Io,
    allocator: std.mem.Allocator,
    ctx: context.AppCtx,
) !void {
    var reader_buf: [512]u8 = undefined;
    var body_buf: [4096]u8 = undefined;
    const body = try h.readBody(request, &reader_buf, &body_buf);

    const parsed = std.json.parseFromSlice(LoginBody, allocator, body, .{}) catch {
        return h.respond400(request, "{\"error\":\"invalid json\"}");
    };
    defer parsed.deinit();

    const pw_hash = password_mod.hash(parsed.value.password, io, allocator) catch |err| {
        std.debug.print("register: hash failed: {}\n", .{err});
        return h.respond500(request);
    };
    defer allocator.free(pw_hash);

    const user = users_q.create(ctx.pool, parsed.value.email, pw_hash, allocator) catch {
        return h.respond400(request, "{\"error\":\"email already registered\"}");
    };
    defer user.deinit();

    const access = issueTokens(io, allocator, ctx, user.id, user.email) catch |err| {
        std.debug.print("register: issueTokens failed: {}\n", .{err});
        return h.respond500(request);
    };
    defer allocator.free(access.jwt);
    defer allocator.free(access.refresh);

    var resp_buf: [512]u8 = undefined;
    const resp = try std.fmt.bufPrint(&resp_buf,
        "{{\"access_token\":\"{s}\",\"refresh_token\":\"{s}\"}}",
        .{ access.jwt, access.refresh });
    try request.respond(resp, .{ .extra_headers = &h.json_cors_headers });
}

pub fn handleLogin(
    request: *std.http.Server.Request,
    io: Io,
    allocator: std.mem.Allocator,
    ctx: context.AppCtx,
) !void {
    var reader_buf: [512]u8 = undefined;
    var body_buf: [4096]u8 = undefined;
    const body = try h.readBody(request, &reader_buf, &body_buf);

    const parsed = std.json.parseFromSlice(LoginBody, allocator, body, .{}) catch {
        return h.respond400(request, "{\"error\":\"invalid json\"}");
    };
    defer parsed.deinit();

    const user = (users_q.findByEmail(ctx.pool, parsed.value.email, allocator) catch {
        return h.respond500(request);
    }) orelse return h.respond401(request);
    defer user.deinit();

    const pw_hash = user.password_hash orelse return h.respond401(request);
    const ok = password_mod.verify(pw_hash, parsed.value.password, io, allocator) catch {
        return h.respond500(request);
    };
    if (!ok) return h.respond401(request);

    const access = issueTokens(io, allocator, ctx, user.id, user.email) catch {
        return h.respond500(request);
    };
    defer allocator.free(access.jwt);
    defer allocator.free(access.refresh);

    var resp_buf: [512]u8 = undefined;
    const resp = try std.fmt.bufPrint(&resp_buf,
        "{{\"access_token\":\"{s}\",\"refresh_token\":\"{s}\"}}",
        .{ access.jwt, access.refresh });
    try request.respond(resp, .{ .extra_headers = &h.json_cors_headers });
}

pub fn handleRefresh(
    request: *std.http.Server.Request,
    io: Io,
    allocator: std.mem.Allocator,
    ctx: context.AppCtx,
) !void {
    _ = io;
    var reader_buf: [512]u8 = undefined;
    var body_buf: [4096]u8 = undefined;
    const body = try h.readBody(request, &reader_buf, &body_buf);

    const parsed = std.json.parseFromSlice(RefreshBody, allocator, body, .{}) catch {
        return h.respond400(request, "{\"error\":\"invalid json\"}");
    };
    defer parsed.deinit();

    const tok_hash = tokens_mod.hashToken(parsed.value.refresh_token, allocator) catch {
        return h.respond500(request);
    };
    defer allocator.free(tok_hash);

    const tok_row = (toks_q.findByHash(ctx.pool, tok_hash, allocator) catch {
        return h.respond500(request);
    }) orelse return h.respond401(request);
    defer tok_row.deinit();

    if (!tok_row.isValid()) return h.respond401(request);

    const user = (users_q.findById(ctx.pool, tok_row.user_id, allocator) catch {
        return h.respond500(request);
    }) orelse return h.respond401(request);
    defer user.deinit();

    const new_jwt = jwt_mod.sign(user.email, ctx.jwt_secret, JWT_TTL_S, allocator) catch {
        return h.respond500(request);
    };
    defer allocator.free(new_jwt);

    var resp_buf: [512]u8 = undefined;
    const resp = try std.fmt.bufPrint(&resp_buf, "{{\"access_token\":\"{s}\"}}", .{new_jwt});
    try request.respond(resp, .{ .extra_headers = &h.json_cors_headers });
}

pub fn handleLogout(
    request: *std.http.Server.Request,
    io: Io,
    allocator: std.mem.Allocator,
    ctx: context.AppCtx,
) !void {
    _ = io;
    var reader_buf: [512]u8 = undefined;
    var body_buf: [4096]u8 = undefined;
    const body = try h.readBody(request, &reader_buf, &body_buf);

    const parsed = std.json.parseFromSlice(LogoutBody, allocator, body, .{}) catch {
        return h.respond400(request, "{\"error\":\"invalid json\"}");
    };
    defer parsed.deinit();

    const tok_hash = tokens_mod.hashToken(parsed.value.refresh_token, allocator) catch {
        return h.respond500(request);
    };
    defer allocator.free(tok_hash);

    toks_q.revoke(ctx.pool, tok_hash) catch {};
    try request.respond("{}", .{ .extra_headers = &h.json_cors_headers });
}

pub fn handleMe(
    request: *std.http.Server.Request,
    io: Io,
    allocator: std.mem.Allocator,
    ctx: context.AppCtx,
) !void {
    _ = io;
    const token = h.extractBearer(request) orelse return h.respond401(request);

    const claims = jwt_mod.verify(token, ctx.jwt_secret, allocator) catch {
        return h.respond401(request);
    };
    defer allocator.free(claims.sub);

    const user = (users_q.findByEmail(ctx.pool, claims.sub, allocator) catch {
        return h.respond500(request);
    }) orelse return h.respond401(request);
    defer user.deinit();

    var resp_buf: [512]u8 = undefined;
    const resp = try std.fmt.bufPrint(&resp_buf,
        "{{\"id\":\"{s}\",\"email\":\"{s}\",\"email_verified\":{s}}}",
        .{ user.id, user.email, if (user.email_verified) "true" else "false" });
    try request.respond(resp, .{ .extra_headers = &h.json_cors_headers });
}

const TokenPair = struct { jwt: []const u8, refresh: []const u8 };

fn issueTokens(
    io: Io,
    allocator: std.mem.Allocator,
    ctx: context.AppCtx,
    user_id: []const u8,
    email: []const u8,
) !TokenPair {
    const access = try jwt_mod.sign(email, ctx.jwt_secret, JWT_TTL_S, allocator);
    errdefer allocator.free(access);

    const refresh = try tokens_mod.generate(io, allocator);
    errdefer allocator.free(refresh);

    const refresh_hash = try tokens_mod.hashToken(refresh, allocator);
    defer allocator.free(refresh_hash);

    const expires_at_us = nowMicroSec() + REFRESH_TTL_US;
    try toks_q.create(ctx.pool, user_id, refresh_hash, expires_at_us, allocator);

    return .{ .jwt = access, .refresh = refresh };
}
