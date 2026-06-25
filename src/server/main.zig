const std = @import("std");
const Io = std.Io;
const sol = @import("sol");
const handlers = @import("handlers.zig");
const context = sol.server.context;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    var port: u16 = 8080;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--port") and i + 1 < args.len) {
            port = std.fmt.parseInt(u16, args[i + 1], 10) catch {
                std.debug.print("invalid port: {s}\n", .{args[i + 1]});
                return;
            };
            i += 1;
        }
    }

    // Read DATABASE_URL and JWT_SECRET from env
    const database_url: ?[]const u8 = if (std.c.getenv("DATABASE_URL")) |raw|
        std.mem.span(raw)
    else
        null;

    const jwt_secret: []const u8 = if (std.c.getenv("JWT_SECRET")) |raw|
        std.mem.span(raw)
    else
        "dev-secret-change-in-production";

    // Init DB pool and run migrations (only if DATABASE_URL is set)
    var maybe_pool: ?*sol.db.pool.Pool = null;
    if (database_url) |url| {
        maybe_pool = sol.db.pool.initFromUrl(io, gpa, url) catch |err| blk: {
            std.debug.print("db pool init failed: {} - running without DB\n", .{err});
            break :blk null;
        };
        if (maybe_pool) |pool| {
            sol.db.migrate.run(pool, sol.db.migrations_embed.all, gpa) catch |err| {
                std.debug.print("migration failed: {}\n", .{err});
            };
        }
    }

    const ctx = context.AppCtx{
        .pool = maybe_pool orelse undefined,
        .has_db = maybe_pool != null,
        .jwt_secret = jwt_secret,
    };

    var addr_buf: [22]u8 = undefined;
    const addr_str = try std.fmt.bufPrint(&addr_buf, "0.0.0.0:{d}", .{port});
    const address = try std.Io.net.IpAddress.parseLiteral(addr_str);
    var listener = try address.listen(io, .{ .reuse_address = true });
    defer listener.deinit(io);

    std.debug.print("sol-server listening on :{d}\n", .{port});

    while (true) {
        const stream = listener.accept(io) catch |err| {
            std.debug.print("accept error: {}\n", .{err});
            continue;
        };
        handleConnection(stream, io, gpa, ctx) catch |err| {
            std.debug.print("connection error: {}\n", .{err});
        };
    }
}

fn handleConnection(
    stream: std.Io.net.Stream,
    io: Io,
    allocator: std.mem.Allocator,
    ctx: context.AppCtx,
) !void {
    defer stream.close(io);

    var recv_buf: [8192]u8 = undefined;
    var send_buf: [128 * 1024]u8 = undefined;
    var net_reader = stream.reader(io, &recv_buf);
    var net_writer = stream.writer(io, &send_buf);
    var http_server = std.http.Server.init(&net_reader.interface, &net_writer.interface);
    var request = try http_server.receiveHead();
    try handlers.dispatch(&request, io, allocator, ctx);
}
