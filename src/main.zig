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
    std.debug.print("client connected!", .{});

    const buf = try allocator.alloc(u8, 100);
    const bytes_read = try client.stream.read(buf);

    const http_200_ok = "HTTP/1.1 200 OK\r\n\r\n";
    const bytes_written = try client.stream.write(http_200_ok);
    client.stream.close();

    std.debug.print("bytes written {} {}", .{ bytes_read, bytes_written });
}
