const std = @import("std");
const net = std.net;
const request = @import("request.zig");

pub fn main() !void {
    // You can use print statements as follows for debugging, they'll be visible when running tests.
    std.debug.print("Logs from your program will appear here!\n", .{});

    const address = try net.Address.resolveIp("127.0.0.1", 4221);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    while (true) {
        std.debug.print("client connected!\n", .{});
        const client = try listener.accept();
        const thread = try std.Thread.spawn(.{}, clientLoop, .{client});
        thread.detach();
    }
}

fn clientLoop(client: std.net.Server.Connection) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const request_buf = try allocator.alloc(u8, 512);
    defer allocator.free(request_buf);
    while (true) {
        const bytes_read = try client.stream.read(request_buf);
        var it = std.mem.splitAny(u8, request_buf[0..bytes_read], "\r\n");
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const arenaAllocator = arena.allocator();
        if (it.next()) |line| {
            const path = request.getPath(line);
            const response = if (std.mem.eql(u8, path, "/"))
                "HTTP/1.1 200 OK\r\n\r\n"
            else if (std.mem.startsWith(u8, path, "/echo"))
                try echoResponse(arenaAllocator, path)
            else if (std.mem.startsWith(u8, path, "/user-agent"))
                try userAgentResponse(arenaAllocator, request_buf[0..bytes_read])
            else
                "HTTP/1.1 404 Not Found\r\n\r\n";

            const bytes_written = try client.stream.write(response);
            std.debug.print("bytes written {} {}", .{ bytes_read, bytes_written });
        }
    }
    client.stream.close();
}

fn echoResponse(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const prefix = "/echo/".len;
    const payload = path[prefix..];
    const payloadLength = payload.len;
    return try std.fmt.allocPrint(allocator, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {d}\r\n\r\n{s}\r\n", .{ payloadLength, payload });
}

fn userAgentResponse(allocator: std.mem.Allocator, requestString: []const u8) ![]const u8 {
    const headers = try request.getHeaders(allocator, requestString);
    const userAgent = headers.get("user-agent");
    if (userAgent) |ua| {
        return try std.fmt.allocPrint(allocator, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {d}\r\n\r\n{s}\r\n", .{ ua.len, ua });
    } else {
        return "HTTP/1.1 404 Not Found\r\n\r\n";
    }
}
