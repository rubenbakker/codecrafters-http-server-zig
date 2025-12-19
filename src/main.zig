const std = @import("std");
const net = std.net;

pub fn main() !void {
    // You can use print statements as follows for debugging, they'll be visible when running tests.
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    std.debug.print("Logs from your program will appear here!\n", .{});

    const address = try net.Address.resolveIp("127.0.0.1", 4221);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    const client = try listener.accept();
    std.debug.print("client connected!\n", .{});

    const request_buf = try allocator.alloc(u8, 512);
    defer allocator.free(request_buf);
    const bytes_read = try client.stream.read(request_buf);
    var it = std.mem.splitAny(u8, request_buf[0..bytes_read], "\r\n");
    if (it.next()) |line| {
        const response = if (std.mem.startsWith(u8, line, "GET / ")) "HTTP/1.1 200 OK\r\n\r\n" else "HTTP/1.1 404 Not Found\r\n\r\n";
        const bytes_written = try client.stream.write(response);
        std.debug.print("bytes written {} {}", .{ bytes_read, bytes_written });
    }

    client.stream.close();
}
