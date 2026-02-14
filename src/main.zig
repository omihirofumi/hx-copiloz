const std = @import("std");
const hx_copiloz = @import("hx_copiloz");

const CompletionProvider = struct {
    triggerCharacters: []const []const u8,
};

const Capabilities = struct {
    completionProvider: CompletionProvider,
};

const Result = struct {
    capabilities: Capabilities,
};

const RpcResponse = struct {
    jsonrpc: []const u8,
    id: []const u8,
    result: Result,
};

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var stdin_buf: [1024]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buf);
    const stdin = &stdin_reader.interface;

    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;

    while (true) {
        const body = readLspBody(allocator, stdin) catch |e| switch (e) {
            error.EndOfStream => break,
            else => return e,
        };
        // defer allocator.free(body);

        std.log.info("<< {s}\n", .{body});

        const parsed: std.json.Parsed(std.json.Value) = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
            std.log.err("parse failed\n", .{});
            continue;
        };
        defer parsed.deinit();

        if (parsed.value != .object) continue;
        const obj = parsed.value.object;

        const method_v = obj.get("method") orelse continue;
        if (method_v != .string) continue;

        const id_v = obj.get("id") orelse continue;

        const method = method_v.string;
        if (!std.mem.eql(u8, method, "initialize")) continue;

        const id = try stringifyValue(allocator, id_v);
        defer allocator.free(id);

        const payload: RpcResponse = .{
            .jsonrpc = "2.0",
            .id = id,
            .result = .{
                .capabilities = .{
                    .completionProvider = .{
                        .triggerCharacters = &[_][]const u8{"."},
                    },
                },
            },
        };

        const resp = try std.json.Stringify.valueAlloc(allocator, payload, .{});
        defer allocator.free(resp);

        try stdout.print("Content-Length: {d}\r\n\r\n", .{resp.len});
        try stdout.writeAll(resp);
        try stdout.flush();
    }
}

fn readLspBody(alloc: std.mem.Allocator, reader: *std.Io.Reader) ![]u8 {
    var header = try std.ArrayList(u8).initCapacity(alloc, 100);
    defer header.deinit(alloc);

    var last4: [4]u8 = .{ 0, 0, 0, 0 };

    while (true) {
        const b = try reader.takeByte();
        try header.append(alloc, b);

        last4[0] = last4[1];
        last4[1] = last4[2];
        last4[2] = last4[3];
        last4[3] = b;

        if (std.mem.eql(u8, &last4, "\r\n\r\n")) break;

        if (header.items.len > 64 * 1024) return error.InvalidHeader;
    }

    const n = try parseContentLength(header.items);

    return try reader.take(n);
}

fn parseContentLength(header: []const u8) !usize {
    const key = "Content-Length:";
    const idx_opt = std.mem.indexOf(u8, header, key) orelse return error.MissingContentLength;

    var i: usize = idx_opt + key.len;

    while (i < header.len and (header[i] == ' ' or header[i] == '\t')) : (i += 1) {}

    var n: usize = 0;
    var saw_digit = false;

    while (i < header.len) : (i += 1) {
        const c = header[i];
        if (c >= '0' and c <= '9') {
            saw_digit = true;
            n = n * 10 + @as(usize, c - '0');
        } else {
            break;
        }
    }

    if (!saw_digit) return error.InvalidContentLength;
    return n;
}

fn stringifyValue(alloc: std.mem.Allocator, v: std.json.Value) ![]const u8 {
    return std.fmt.allocPrint(alloc, "{f}", .{std.json.fmt(v, .{})});
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
