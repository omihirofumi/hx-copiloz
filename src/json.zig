const std = @import("std");

const Value = union(enum) {
    Null,
    Object: std.StringArrayHashMap(Value),
    Array: std.ArrayList(Value),
    String: std.ArrayList(u8),
    Number: f64,
    Bool: bool,

    pub fn stringify(self: @This(), a: std.mem.Allocator, w: anytype) !void {
        switch (self) {
            .Object => |v| {
                try w.writeByte('{');
                for (v.keys(), 0..) |key, i| {
                    if (i > 0) try w.writeByte(',');
                    var bytes = std.ArrayList(u8){};
                    defer bytes.deinit(a);
                    try bytes.print(a, "{}", .{key});
                    try (Value{ .String = bytes }).stringify(a, w);
                    try w.writeByte(':');
                    try v.get(key).?.stringify(a, w);
                }
                try w.writeByte('}');
            },
            .String => |v| {
                try w.writeByte('"');
                for (v.items) |c| {
                    switch (c) {
                        '\\' => try w.writeAll("\\\\"),
                        '"' => try w.writeAll("\\\""),
                        '\n' => try w.writeAll("\\n"),
                        '\r' => try w.writeAll("\\r"),
                        else => try w.writeByte(c),
                    }
                }
                try w.writeByte('"');
            },
        }
    }
};
