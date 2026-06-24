const std = @import("std");

pub const cors_headers = [_]std.http.Header{
    .{ .name = "access-control-allow-origin", .value = "*" },
    .{ .name = "access-control-allow-methods", .value = "GET, POST, OPTIONS" },
    .{ .name = "access-control-allow-headers", .value = "content-type, authorization" },
};

pub const json_cors_headers = cors_headers ++ [_]std.http.Header{
    .{ .name = "content-type", .value = "application/json" },
};

pub fn respond400(request: *std.http.Server.Request, msg: []const u8) !void {
    try request.respond(msg, .{ .status = .bad_request, .extra_headers = &json_cors_headers });
}

pub fn respond401(request: *std.http.Server.Request) !void {
    try request.respond("{\"error\":\"unauthorized\"}", .{
        .status = .unauthorized,
        .extra_headers = &json_cors_headers,
    });
}

pub fn respond500(request: *std.http.Server.Request) !void {
    try request.respond("{\"error\":\"internal server error\"}", .{
        .status = .internal_server_error,
        .extra_headers = &json_cors_headers,
    });
}

/// Read POST body. reader_buf is used by the body reader internally.
/// dest receives the body bytes. Returns slice of dest that was written.
pub fn readBody(request: *std.http.Server.Request, reader_buf: []u8, dest: []u8) ![]u8 {
    var reader = request.readerExpectNone(reader_buf);
    const n = try reader.readSliceShort(dest);
    return dest[0..n];
}

/// Extract Bearer token from Authorization header. Returns slice into header value.
pub fn extractBearer(request: *const std.http.Server.Request) ?[]const u8 {
    var it = request.iterateHeaders();
    while (it.next()) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, "authorization")) {
            const val = header.value;
            if (std.mem.startsWith(u8, val, "Bearer ")) {
                return val["Bearer ".len..];
            }
        }
    }
    return null;
}
