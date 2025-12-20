const std = @import("std");
const String = @import("string").String;

const HeaderMap = std.StringHashMap([]const u8);

pub const Method = enum { GET, POST, PUT, PATCH, DELETE };

pub const Request = struct {
    method: Method,
    path: []const u8,
    headers: HeaderMap,
    body: ?[]const u8,

    const Self = @This();

    pub fn startsWith(self: Self, method: Method, needle: []const u8) bool {
        return self.method == method and std.mem.startsWith(u8, self.path, needle);
    }

    pub fn equals(self: Self, method: Method, needle: []const u8) bool {
        return self.method == method and std.mem.eql(u8, self.path, needle);
    }

    pub fn parse(allocator: std.mem.Allocator, requestString: []const u8) !Request {
        const headers = try getHeaders(allocator, requestString);
        return .{ .method = getMethod(requestString), .path = getPath(requestString), .headers = headers, .body = try getBody(headers, requestString) };
    }
};

fn getHeaders(allocator: std.mem.Allocator, request: []const u8) !HeaderMap {
    var headerMap = HeaderMap.init(allocator);
    var it = std.mem.splitAny(u8, request, "\n");
    _ = it.next(); // skip header
    while (it.next()) |line| {
        const line1 = std.mem.trim(u8, line, "\r");
        if (line1.len == 0) break;
        var wordIt = std.mem.splitAny(u8, line1, ":");
        var key: []const u8 = undefined;
        var value: []const u8 = undefined;
        var keyString = String.init(allocator);
        if (wordIt.next()) |name| {
            try keyString.setStr(name);
            keyString.toLowercase();
            key = keyString.str();
            if (wordIt.next()) |v| {
                value = std.mem.trim(u8, v, " ");
            }
        }
        std.debug.print("key: {s}, value: {s}\n", .{ key, value });
        try headerMap.put(key, value);
    }
    return headerMap;
}

fn getPath(input: []const u8) []const u8 {
    var it = std.mem.splitAny(u8, input, " ");
    _ = it.next();
    return if (it.next()) |path| path else "";
}

fn getMethod(input: []const u8) Method {
    var it = std.mem.splitAny(u8, input, " ");
    return if (it.next()) |method| std.meta.stringToEnum(Method, method) orelse Method.GET else Method.GET;
}

fn getBody(headers: HeaderMap, input: []const u8) !?[]const u8 {
    if (headers.get("content-length")) |contentLengthString| {
        const contentLength = try std.fmt.parseInt(usize, contentLengthString, 10);
        const fromIdx = input.len - contentLength;
        if (fromIdx > 0) {
            return input[fromIdx..];
        }
    }
    return null;
}

test "getHeaders" {
    const request = "GET /user-agent HTTP/1.1\r\nHost: localhost:4221\r\nUser-Agent: foobar/1.2.3\r\nAccept: */*\r\n\r\n";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const headerMap = try getHeaders(arena.allocator(), request);
    try std.testing.expect(headerMap.count() == 3);
    const userAgent = headerMap.get("user-agent") orelse "not-found";
    std.debug.print("user agent: {s}", .{userAgent});
    try std.testing.expect(std.mem.eql(u8, "foobar/1.2.3", userAgent));
}
