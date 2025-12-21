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

pub const HeaderName = enum {
    ContentType,
    ContentLength,
    ContentEncoding,
    Connection,

    const Self = @This();

    pub fn toString(self: Self) []const u8 {
        return switch (self) {
            Self.ContentType => "Content-Type",
            Self.ContentLength => "Context-Length",
            Self.ContentEncoding => "Content-Encoding",
            Self.Connection => "Connection",
        };
    }
};

const Header = struct {
    name: HeaderName,
    value: []const u8,

    const Self = @This();

    pub fn writeToStream(self: Self, stream: std.net.Stream) !void {
        _ = try stream.write(self.name.toString());
        _ = try stream.write(": ");
        _ = try stream.write(self.value);
        _ = try stream.write("\r\n");
    }
};

const HeaderList = std.ArrayList(Header);

pub const ResponseBuilder = struct {
    allocator: std.mem.Allocator,
    statusCode: StatusCode,
    headers: ?HeaderList,
    gzip: bool,
    contentType: ?[]const u8,
    body: ?[]const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, statusCode: StatusCode) Self {
        return .{ .allocator = allocator, .statusCode = statusCode, .headers = null, .body = null, .gzip = false, .contentType = null };
    }

    pub fn addHeader(self: *Self, name: HeaderName, value: []const u8) !void {
        if (self.headers == null) {
            self.headers = try HeaderList.initCapacity(self.allocator, 10);
        }
        if (self.headers) |_| {
            const header: Header = .{ .name = name, .value = value };
            try self.headers.?.append(self.allocator, header);
        }
    }

    pub fn setBody(self: *Self, body: []const u8, contentType: []const u8, gzipContent: bool) void {
        self.body = body;
        self.contentType = contentType;
        self.gzip = gzipContent;
    }

    pub fn writeToStream(self: Self, stream: std.net.Stream) !void {
        const code = self.statusCode;
        _ = try stream.write(try std.fmt.allocPrint(self.allocator, "HTTP/1.1 {d} {s}\r\n", .{ code, code.toString() }));
        if (self.headers) |headers| {
            for (headers.items) |header| {
                try header.writeToStream(stream);
            }
        }
        if (self.body) |body| {
            var content1 = body;
            var len = content1.len;
            if (self.gzip) {
                const header: Header = .{ .name = HeaderName.ContentEncoding, .value = "gzip" };
                try header.writeToStream(stream);
                const compressed = try self.allocator.alloc(u8, 8192);
                var reader = std.Io.Reader.fixed(body);
                var writer = std.Io.Writer.fixed(compressed);
                try gzip.compress(&reader, &writer, .{});
                try writer.flush();
                len = writer.end;
                content1 = compressed[0..writer.end];
            }
            const header: Header = .{ .name = HeaderName.ContentLength, .value = try std.fmt.allocPrint(self.allocator, "{d}", .{len}) };
            try header.writeToStream(stream);
            _ = try stream.write("\r\n");
            _ = try stream.write(content1);
        } else {
            _ = try stream.write("\r\n");
        }
    }
};
