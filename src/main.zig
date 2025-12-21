const std = @import("std");
const net = std.net;
const Request = @import("request.zig").Request;
const Method = @import("request.zig").Method;
const Respond = @import("response.zig").Respond;
const StatusCode = @import("response.zig").StatusCode;

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
    const stream = client.stream;
    while (true) {
        const bytes_read = stream.read(request_buf) catch {
            std.debug.print("error reading from client\n", .{});
            break;
        };
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const arenaAllocator = arena.allocator();
        const req = try Request.parse(allocator, request_buf[0..bytes_read]);
        if (req.equals(Method.GET, "/")) try Respond.ok(allocator, stream) else if (req.startsWith(Method.GET, "/echo/"))
            try echoResponse(arenaAllocator, req, stream)
        else if (req.startsWith(Method.GET, "/user-agent"))
            try userAgentResponse(arenaAllocator, req, stream)
        else if (req.startsWith(Method.GET, "/files/")) try fileResponse(arenaAllocator, req, directory, stream) else if (req.startsWith(Method.POST, "/files/")) try writeFileResponse(arenaAllocator, req, directory, stream) else try Respond.notFound(allocator, stream);
        if (req.headers.get("connection")) |value| {
            if (std.mem.eql(u8, "close", value)) {
                std.debug.print("{s}", .{value});
                break;
            }
        }
    }
    stream.close();
}

fn echoResponse(allocator: std.mem.Allocator, req: Request, stream: std.net.Stream) !void {
    const prefix = "/echo/".len;
    const payload = req.path[prefix..];
    try Respond.statusCode(allocator, stream, StatusCode.Ok);
    try Respond.addBody(allocator, stream, req.hasGzipAcceptEncoding(), "text/plain", payload);
}

fn userAgentResponse(allocator: std.mem.Allocator, req: Request, stream: std.net.Stream) !void {
    const userAgent = req.headers.get("user-agent");
    if (userAgent) |ua| {
        try Respond.statusCode(allocator, stream, StatusCode.Ok);
        try Respond.addBody(allocator, stream, req.hasGzipAcceptEncoding(), "text/plain", ua);
    } else {
        return Respond.notFound(allocator, stream);
    }
}

fn fileResponse(allocator: std.mem.Allocator, req: Request, directory: ?[]const u8, stream: std.net.Stream) !void {
    const prefix = "/files/".len;
    const filename = req.path[prefix..];
    if (directory) |dir| {
        const path = try std.fs.path.join(allocator, &[_][]const u8{ dir, filename });
        std.fs.accessAbsolute(path, .{ .mode = .read_only }) catch {
            return Respond.notFound(allocator, stream);
        };
        const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
        defer file.close();
        const content = try std.fs.File.readToEndAlloc(file, allocator, 99999999);
        try Respond.statusCode(allocator, stream, StatusCode.Ok);
        try Respond.addBody(allocator, stream, req.hasGzipAcceptEncoding(), "application/octet-stream", content);
    } else return Respond.notFound(allocator, stream);
}

fn writeFileResponse(allocator: std.mem.Allocator, req: Request, directory: ?[]const u8, stream: std.net.Stream) !void {
    const prefix = "/files/".len;
    const filename = req.path[prefix..];
    if (directory) |dir| {
        if (req.body) |body| {
            const path = try std.fs.path.join(allocator, &[_][]const u8{ dir, filename });
            const file = try std.fs.cwd().createFile(path, .{});
            defer file.close();
            _ = try std.fs.File.writeAll(file, body);
            try Respond.created(allocator, stream);
        } else {
            try Respond.badRequest(allocator, stream);
        }
    } else try Respond.notFound(allocator, stream);
}
