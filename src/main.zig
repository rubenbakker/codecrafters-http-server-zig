const std = @import("std");
const net = std.net;
const Request = @import("request.zig").Request;
const Method = @import("request.zig").Method;

pub fn main() !void {
    // You can use print statements as follows for debugging, they'll be visible when running tests.
    std.debug.print("Logs from your program will appear here!\n", .{});
    var argsIt = std.process.args();
    var directory: ?[]const u8 = null;
    if (argsIt.next()) |_| {
        if (argsIt.next()) |arg| {
            if (std.mem.eql(u8, "--directory", arg)) {
                if (argsIt.next()) |dir| {
                    directory = dir;
                }
            }
        }
    }
    const address = try net.Address.resolveIp("127.0.0.1", 4221);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    while (true) {
        const client = try listener.accept();
        std.debug.print("client connected!\n", .{});
        const thread = try std.Thread.spawn(.{}, clientLoop, .{ client, directory });
        thread.detach();
    }
}

fn clientLoop(client: std.net.Server.Connection, directory: ?[]const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const request_buf = try allocator.alloc(u8, 512);
    defer allocator.free(request_buf);
    const bytes_read = client.stream.read(request_buf) catch {
        std.debug.print("error reading from client\n", .{});
        return;
    };
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arenaAllocator = arena.allocator();
    const req = try Request.parse(allocator, request_buf[0..bytes_read]);
    const response = if (req.equals(Method.GET, "/"))
        "HTTP/1.1 200 OK\r\n\r\n"
    else if (req.startsWith(Method.GET, "/echo/"))
        try echoResponse(arenaAllocator, req.path)
    else if (req.startsWith(Method.GET, "/user-agent"))
        try userAgentResponse(arenaAllocator, req)
    else if (req.startsWith(Method.GET, "/files/")) try fileResponse(arenaAllocator, req, directory) else if (req.startsWith(Method.POST, "/files/")) try writeFileResponse(arenaAllocator, req, directory) else "HTTP/1.1 404 Not Found\r\n\r\n";

    _ = client.stream.write(response) catch {
        std.debug.print("error writing to client\n", .{});
    };
    client.stream.close();
}

fn echoResponse(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const prefix = "/echo/".len;
    const payload = path[prefix..];
    return try std.fmt.allocPrint(allocator, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {d}\r\n\r\n{s}\r\n", .{ payload.len, payload });
}

fn userAgentResponse(allocator: std.mem.Allocator, req: Request) ![]const u8 {
    const userAgent = req.headers.get("user-agent");
    if (userAgent) |ua| {
        return try std.fmt.allocPrint(allocator, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {d}\r\n\r\n{s}\r\n", .{ ua.len, ua });
    } else {
        return "HTTP/1.1 404 Not Found\r\n\r\n";
    }
}

fn fileResponse(allocator: std.mem.Allocator, req: Request, directory: ?[]const u8) ![]const u8 {
    const prefix = "/files/".len;
    const filename = req.path[prefix..];
    if (directory) |dir| {
        const path = try std.fs.path.join(allocator, &[_][]const u8{ dir, filename });
        std.fs.accessAbsolute(path, .{ .mode = .read_only }) catch {
            return "HTTP/1.1 404 Not Found\r\n\r\n";
        };
        const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
        defer file.close();
        const content = try std.fs.File.readToEndAlloc(file, allocator, 99999999);
        return try std.fmt.allocPrint(allocator, "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: {d}\r\n\r\n{s}\r\n", .{ content.len, content });
    } else return "HTTP/1.1 404 Not Found\r\n\r\n";
}

fn writeFileResponse(allocator: std.mem.Allocator, req: Request, directory: ?[]const u8) ![]const u8 {
    const prefix = "/files/".len;
    const filename = req.path[prefix..];
    if (directory) |dir| {
        if (req.body) |body| {
            const path = try std.fs.path.join(allocator, &[_][]const u8{ dir, filename });
            const file = try std.fs.cwd().createFile(path, .{});
            defer file.close();
            _ = try std.fs.File.writeAll(file, body);
            return try std.fmt.allocPrint(allocator, "HTTP/1.1 201 Created", .{});
        } else {
            return "HTTP/1.1 400 Bad Request\r\n\r\n";
        }
    } else return "HTTP/1.1 404 Not Found\r\n\r\n";
}
