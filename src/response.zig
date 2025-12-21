const std = @import("std");
const gzip = @import("gzip.zig");

pub const StatusCode = enum(u32) {
    Ok = 200,
    Created = 201,
    BadRequest = 400,
    NotFound = 404,

    const Self = @This();

    fn toString(self: Self) []const u8 {
        return switch (self) {
            Self.Ok => "OK",
            Self.Created => "Created",
            Self.BadRequest => "Bad Request",
            Self.NotFound => "Not Found",
        };
    }
};

pub const Respond = struct {
    pub fn ok(allocator: std.mem.Allocator, stream: std.net.Stream) !void {
        try onlyStatusCode(allocator, stream, StatusCode.Ok);
    }

    pub fn created(allocator: std.mem.Allocator, stream: std.net.Stream) !void {
        try onlyStatusCode(allocator, stream, StatusCode.Created);
    }

    pub fn badRequest(allocator: std.mem.Allocator, stream: std.net.Stream) !void {
        try onlyStatusCode(allocator, stream, StatusCode.BadRequest);
    }

    pub fn notFound(allocator: std.mem.Allocator, stream: std.net.Stream) !void {
        try onlyStatusCode(allocator, stream, StatusCode.NotFound);
    }

    fn onlyStatusCode(allocator: std.mem.Allocator, stream: std.net.Stream, code: StatusCode) !void {
        _ = try statusCode(allocator, stream, code);
        _ = try stream.write("\r\n");
    }

    pub fn statusCode(allocator: std.mem.Allocator, stream: std.net.Stream, code: StatusCode) !void {
        _ = try stream.write(try std.fmt.allocPrint(allocator, "HTTP/1.1 {d} {s}\r\n", .{ code, code.toString() }));
    }

    pub fn addHeader(stream: std.net.Stream, name: []const u8, value: []const u8) !void {
        _ = try stream.write(name);
        _ = try stream.write(": ");
        _ = try stream.write(value);
        _ = try stream.write("\r\n");
    }

    pub fn finishHeaders(stream: std.net.Stream) !void {
        _ = try stream.write("\r\n");
    }

    pub fn addBody(allocator: std.mem.Allocator, stream: std.net.Stream, gzipEncode: bool, contentType: []const u8, content: []const u8) !void {
        var content1 = content;
        var len = content.len;
        if (gzipEncode) {
            try addHeader(stream, "Content-Encoding", "gzip");
            const compressed = try allocator.alloc(u8, 8192);
            var reader = std.Io.Reader.fixed(content);
            var writer = std.Io.Writer.fixed(compressed);
            try gzip.compress(&reader, &writer, .{});
            try writer.flush();
            len = writer.end;
            content1 = compressed[0..writer.end];
        }
        try addHeader(stream, "Content-Type", contentType);
        try addHeader(stream, "Content-Length", try std.fmt.allocPrint(allocator, "{d}", .{len}));
        _ = try stream.write("\r\n");
        _ = try stream.write(content1);
    }
};
