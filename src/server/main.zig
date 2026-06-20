const std = @import("std");
const Io = std.Io;
const handlers = @import("handlers.zig");

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
        handleConnection(stream, io, gpa) catch |err| {
            std.debug.print("connection error: {}\n", .{err});
        };
    }
}

fn handleConnection(
    stream: std.Io.net.Stream,
    io: Io,
    allocator: std.mem.Allocator,
) !void {
    defer stream.close(io);

    var recv_buf: [8192]u8 = undefined;
    var send_buf: [128 * 1024]u8 = undefined;
    var net_reader = stream.reader(io, &recv_buf);
    var net_writer = stream.writer(io, &send_buf);
    var http_server = std.http.Server.init(&net_reader.interface, &net_writer.interface);
    var request = try http_server.receiveHead();
    try handlers.dispatch(&request, io, allocator);
}
