const std = @import("std");
const String = @import("string").String;

const HeaderMap = std.StringHashMap([]const u8);

pub const Request = struct {
    path: []const u8,
    headers: HeaderMap,

    const Self = @This();

    pub fn startsWith(self: Self, needle: []const u8) bool {
        return std.mem.startsWith(u8, self.path, needle);
    }

    pub fn parse(allocator: std.mem.Allocator, requestString: []const u8) !Request {
        var it = std.mem.splitAny(u8, requestString, "\r\n");
        var request: Request = .{ .path = "", .headers = try getHeaders(allocator, requestString) };
        if (it.next()) |line| {
            request.path = getPath(line);
        }
        return request;
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
    _ = it.next(); // method
    if (it.next()) |word| return word;
    return "";
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
