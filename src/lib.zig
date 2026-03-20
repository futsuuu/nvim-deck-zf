const builtin = @import("builtin");
const std = @import("std");
const zf = @import("zf");

comptime {
    @export(&InputStrings.getRank, .{ .name = "deck_zf_InputStrings_getRank" });
    @export(&InputStrings.getHighlights, .{ .name = "deck_zf_InputStrings_getHighlights" });
}

pub const InputStrings = extern struct {
    ptr: [*]const u8,
    query_len: u32,
    text_len: u32,
    text_to_lower: bool,

    /// Only used for testing.
    fn new(
        comptime query: []const u8,
        comptime text: []const u8,
        opts: struct { text_to_lower: bool = false },
    ) InputStrings {
        return .{
            .ptr = query ++ text,
            .query_len = query.len,
            .text_len = text.len,
            .text_to_lower = opts.text_to_lower,
        };
    }

    inline fn getQuery(self: InputStrings) []const u8 {
        return self.ptr[0..self.query_len];
    }

    inline fn getText(self: InputStrings) []const u8 {
        return self.ptr[self.query_len..][0..self.text_len];
    }

    fn getZfOptions(self: InputStrings) zf.RankTokenOptions {
        return .{
            .to_lower = self.text_to_lower,
            .filename = std.fs.path.basename(self.getText()),
            .strict_path = std.mem.indexOfScalar(u8, self.getQuery(), std.fs.path.sep) != null,
        };
    }

    fn getRank(self: InputStrings) callconv(.c) f64 {
        const rank = zf.rankToken(self.getText(), self.getQuery(), self.getZfOptions()) orelse {
            return 0;
        };
        if (rank < 0) {
            return 0;
        }
        return 1 / (rank + 1);
    }

    test getRank {
        const query = "foo";
        const text1 = "foo/bar.txt";
        const text2 = "bar/foo.txt";
        try std.testing.expect(new(query, text1, .{}).getRank() < new(query, text2, .{}).getRank());
    }

    test "getRank with text_to_lower" {
        try std.testing.expectEqual(0, new("fo", "FOO", .{ .text_to_lower = false }).getRank());
        try std.testing.expect(0 < new("fo", "FOO", .{ .text_to_lower = true }).getRank());
    }

    fn getHighlights(self: InputStrings, buf: HighlightBuffer) callconv(.c) u32 {
        const matched_indices = zf.highlightToken(
            self.getText(),
            self.getQuery(),
            buf.asMatchedIndexBuffer(),
            self.getZfOptions(),
        );
        return buf.convertMatchedIndicesToHighlights(matched_indices);
    }

    test getHighlights {
        const query = "abdegh";
        const text = "abcdefgh";

        var buf: [query.len]Highlight = undefined;
        const count = new(query, text, .{}).getHighlights(.new(&buf));

        try std.testing.expectEqualSlices(Highlight, &.{
            .{ .col = 0, .end_col = 2 },
            .{ .col = 3, .end_col = 5 },
            .{ .col = 6, .end_col = 8 },
        }, buf[0..count]);
    }

    test "getHighlights with text_to_lower" {
        var buf: [2]Highlight = undefined;

        const count_without = new("fo", "FOO", .{ .text_to_lower = false }).getHighlights(.new(&buf));
        try std.testing.expectEqual(0, count_without);

        const count_with = new("fo", "FOO", .{ .text_to_lower = true }).getHighlights(.new(&buf));
        try std.testing.expectEqualSlices(Highlight, &.{
            .{ .col = 0, .end_col = 2 },
        }, buf[0..count_with]);
    }
};

pub const Highlight = extern struct {
    col: u32 align(@sizeOf(u64)),
    end_col: u32,

    fn fromIndex(col: usize) Highlight {
        return .{
            .col = @intCast(col),
            .end_col = @intCast(col + 1),
        };
    }
};

pub const HighlightBuffer = extern struct {
    ptr: [*]Highlight,
    capacity: u32,

    /// Only used for testing.
    fn new(buf: []Highlight) HighlightBuffer {
        return .{
            .ptr = buf.ptr,
            .capacity = @intCast(buf.len),
        };
    }

    comptime {
        std.debug.assert(@bitSizeOf(Highlight) == 64);
    }

    /// Returns the buffer of mached character index.
    inline fn asMatchedIndexBuffer(self: HighlightBuffer) []usize {
        // To avoid overwriting the unread matched character indices by
        // highlights in `convertMatchedIndicesToHighlights()`, reserve the
        // front half of `self.ptr[0..self.capacity]` as unused on 32-bit
        // environments.
        return switch (@bitSizeOf(usize)) {
            //    indices |   0   |   1   |   2   |   3   |   4   |
            // highlights |  0,1  |  1,2  |  2,3  |  3,4  |  4,5  |
            64 => @as([*]u64, @ptrCast(self.ptr))[0..self.capacity],
            //    indices |   .   .   .   .   | 0 | 1 | 2 | 3 | 4 |
            // highlights |  0,1  |  1,2  |  2,3  |  3,4  |  4,5  |
            32 => @as([*]u32, @ptrCast(self.ptr))[self.capacity..][0..self.capacity],
            else => unreachable,
        };
    }

    test asMatchedIndexBuffer {
        var buf: [15]Highlight = undefined;
        const self: HighlightBuffer = .new(&buf);
        try std.testing.expectEqual(15, self.asMatchedIndexBuffer().len);
    }

    fn convertMatchedIndicesToHighlights(
        self: HighlightBuffer,
        /// must be the prefix of the returned value of `asMatchedIndexBuffer()`
        matched_indices: []const usize,
    ) u32 {
        if (builtin.mode == .Debug) {
            const index_buf = self.asMatchedIndexBuffer();
            std.debug.assert(matched_indices.ptr == index_buf.ptr);
            std.debug.assert(matched_indices.len <= index_buf.len);
        }
        if (matched_indices.len == 0) {
            return 0;
        }
        var read_cursor: u32 = 0; // index of `matched_indices`
        var write_cursor: u32 = 0; // index of `self.ptr`
        var pending: Highlight = .fromIndex(matched_indices[read_cursor]);
        read_cursor += 1;
        while (read_cursor < matched_indices.len) : (read_cursor += 1) {
            const matched_index: u32 = @intCast(matched_indices[read_cursor]);
            if (matched_index <= pending.end_col) {
                if (pending.end_col < matched_index + 1) {
                    pending.end_col = matched_index + 1;
                }
                continue;
            }
            self.ptr[write_cursor] = pending;
            write_cursor += 1;
            pending = .fromIndex(matched_index);
        }
        self.ptr[write_cursor] = pending;
        write_cursor += 1;
        return write_cursor;
    }

    test convertMatchedIndicesToHighlights {
        var buf: [8]Highlight = undefined;
        const self: HighlightBuffer = .new(&buf);
        const index_buf = self.asMatchedIndexBuffer();
        const matched_indices = [_]usize{ 0, 1, 2, 4, 5, 7 };
        @memcpy(index_buf[0..matched_indices.len], &matched_indices);

        const count = self.convertMatchedIndicesToHighlights(index_buf[0..matched_indices.len]);

        try std.testing.expectEqualSlices(Highlight, &.{
            .{ .col = 0, .end_col = 3 },
            .{ .col = 4, .end_col = 6 },
            .{ .col = 7, .end_col = 8 },
        }, buf[0..count]);
    }
};

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
