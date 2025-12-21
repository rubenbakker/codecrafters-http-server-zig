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
            var compressed_buffer: [1024]u8 = undefined;
            var input_reader = std.Io.Reader.fixed(content);
            var fixed_writer = std.Io.Writer.fixed(&compressed_buffer);
            try gzip.compress(&input_reader, &fixed_writer, .{});
            try fixed_writer.flush();
            len = fixed_writer.end;
            content1 = &compressed_buffer;
        }
        try addHeader(stream, "Content-Type", contentType);
        try addHeader(stream, "Content-Length", try std.fmt.allocPrint(allocator, "{d}", .{len}));
        _ = try stream.write("\r\n");
        _ = try stream.write(content1);
    }
};

// const CompressionResult = struct { len: usize, content: []const u8 };

//     fn gzipString(content: []const u8) !CompressionResult {
//         var compressed_buffer: [1024]u8 = undefined;
//         var fixed_writer = std.Io.Writer.fixed(&compressed_buffer);
//
//         var input_buffer: [1024]u8 = undefined;
//         @memcpy(input_buffer[0..content.len], content);
//         var input_reader = std.Io.Reader.fixed(input_buffer[0..content.len]);
//
//         try gzip.compress(&input_reader, &fixed_writer, .{});
//
//         // Find the end of compressed data by checking for non-zero bytes
//         var written: usize = 0;
//         for (compressed_buffer, 0..) |byte, i| {
//             if (byte != 0) written = i + 1;
//         }
//         return .{ .len = written, .content = compressed_buffer[0..written] };
//     }
// };
