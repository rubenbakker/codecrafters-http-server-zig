const std = @import("std");
const net = std.net;
const Request = @import("request.zig").Request;
const Method = @import("request.zig").Method;
const ResponseBuilder = @import("response.zig").ResponseBuilder;
const StatusCode = @import("response.zig").StatusCode;
const HeaderName = @import("response.zig").HeaderName;

pub fn main() !void {
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
        var responseBuilder = ResponseBuilder.init(allocator, StatusCode.NotFound);
        if (req.equals(Method.GET, "/")) {
            responseBuilder = ResponseBuilder.init(allocator, StatusCode.Ok);
        } else if (req.startsWith(Method.GET, "/echo/")) {
            responseBuilder = try echoResponse(arenaAllocator, req);
        } else if (req.startsWith(Method.GET, "/user-agent")) {
            responseBuilder = try userAgentResponse(arenaAllocator, req);
        } else if (req.startsWith(Method.GET, "/files/")) {
            responseBuilder = try fileResponse(arenaAllocator, req, directory);
        } else if (req.startsWith(Method.POST, "/files/")) {
            responseBuilder = try writeFileResponse(arenaAllocator, req, directory);
        }
        var closeConnection = false;
        if (req.headers.get("connection")) |value| {
            if (std.mem.eql(u8, "close", value)) {
                try responseBuilder.addHeader(HeaderName.Connection, "close");
                closeConnection = true;
            }
        }
        responseBuilder.writeToStream(stream) catch {
            std.debug.print("[WARN] Couldn't write response to client\n");
        };
        if (closeConnection) {
            break;
        }
    }
    stream.close();
}

fn echoResponse(allocator: std.mem.Allocator, req: Request) !ResponseBuilder {
    const prefix = "/echo/".len;
    const payload = req.path[prefix..];
    var builder = ResponseBuilder.init(allocator, StatusCode.Ok);
    builder.setBody(payload, "text/plain", req.hasGzipAcceptEncoding());
    return builder;
}

fn userAgentResponse(allocator: std.mem.Allocator, req: Request) !ResponseBuilder {
    const userAgent = req.headers.get("user-agent");
    if (userAgent) |ua| {
        var builder = ResponseBuilder.init(allocator, StatusCode.Ok);
        builder.setBody(ua, "text/plain", req.hasGzipAcceptEncoding());
        return builder;
    } else {
        return ResponseBuilder.init(allocator, StatusCode.NotFound);
    }
}

fn fileResponse(allocator: std.mem.Allocator, req: Request, directory: ?[]const u8) !ResponseBuilder {
    const prefix = "/files/".len;
    const filename = req.path[prefix..];
    if (directory) |dir| {
        const path = try std.fs.path.join(allocator, &[_][]const u8{ dir, filename });
        std.fs.accessAbsolute(path, .{ .mode = .read_only }) catch {
            return ResponseBuilder.init(allocator, StatusCode.NotFound);
        };
        const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
        defer file.close();
        const content = try std.fs.File.readToEndAlloc(file, allocator, 99999999);
        var builder = ResponseBuilder.init(allocator, StatusCode.Ok);
        builder.setBody(content, "application/octet-stream", req.hasGzipAcceptEncoding());
        return builder;
    } else return ResponseBuilder.init(allocator, StatusCode.NotFound);
}

fn writeFileResponse(allocator: std.mem.Allocator, req: Request, directory: ?[]const u8) !ResponseBuilder {
    const prefix = "/files/".len;
    const filename = req.path[prefix..];
    if (directory) |dir| {
        if (req.body) |body| {
            const path = try std.fs.path.join(allocator, &[_][]const u8{ dir, filename });
            const file = try std.fs.cwd().createFile(path, .{});
            defer file.close();
            _ = try std.fs.File.writeAll(file, body);

            return ResponseBuilder.init(allocator, StatusCode.Created);
        } else {
            return ResponseBuilder.init(allocator, StatusCode.BadRequest);
        }
    } else return ResponseBuilder.init(allocator, StatusCode.NotFound);
}
