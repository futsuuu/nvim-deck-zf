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

    /// Only used for testing.
    fn new(comptime query: []const u8, comptime text: []const u8) InputStrings {
        return .{
            .ptr = query ++ text,
            .query_len = query.len,
            .text_len = text.len,
        };
    }

    inline fn getQuery(self: InputStrings) []const u8 {
        return self.ptr[0..self.query_len];
    }

    inline fn getText(self: InputStrings) []const u8 {
        return self.ptr[self.query_len..][0..self.text_len];
    }

    fn getRank(self: InputStrings) callconv(.c) f64 {
        const opts: zf.RankTokenOptions = .{
            .filename = std.fs.path.basename(self.getText()),
        };
        const rank = zf.rankToken(self.getText(), self.getQuery(), opts) orelse {
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
        try std.testing.expect(new(query, text1).getRank() < new(query, text2).getRank());
    }

    fn getHighlights(self: InputStrings, buf: HighlightBuffer) callconv(.c) u32 {
        const opts: zf.RankTokenOptions = .{
            .filename = std.fs.path.basename(self.getText()),
        };
        const matched_indices = zf.highlightToken(
            self.getText(),
            self.getQuery(),
            buf.asMatchedIndexBuffer(),
            opts,
        );
        return buf.convertMatchedIndicesToHighlights(matched_indices);
    }

    test getHighlights {
        const query = "abdegh";
        const text = "abcdefgh";

        var buf: [query.len]Highlight = undefined;
        const count = new(query, text).getHighlights(.new(&buf));

        try std.testing.expectEqualSlices(Highlight, &.{
            .{ .col = 0, .end_col = 2 },
            .{ .col = 3, .end_col = 5 },
            .{ .col = 6, .end_col = 8 },
        }, buf[0..count]);
    }
};

pub const Highlight = extern struct {
    col: u32 align(@sizeOf(u64)),
    end_col: u32,
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

    /// Returns the buffer of mached character index.
    inline fn asMatchedIndexBuffer(self: HighlightBuffer) []usize {
        return @ptrCast(self.ptr[0..self.capacity]);
    }

    test asMatchedIndexBuffer {
        var buf: [15]Highlight = undefined;
        const self: HighlightBuffer = .new(&buf);
        try std.testing.expectEqual(
            switch (@bitSizeOf(usize)) {
                64 => 15,
                32 => 30,
                else => unreachable,
            },
            self.asMatchedIndexBuffer().len,
        );
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
        comptime std.debug.assert(@bitSizeOf(Highlight) == 64);
        if (@bitSizeOf(usize) == 64) {
            // When the size of `Highlight` matches `usize`, we can read the
            // matched character indices (`[]usize`) from the front and write the
            // highlight ranges (`[]Highlight`) from the front simultaneously.
            var out_index: usize = 0;
            var range_start: u32 = @intCast(matched_indices[0]);
            var range_end: u32 = range_start + 1;
            var i: usize = 1;
            while (i < matched_indices.len) : (i += 1) {
                const index: u32 = @intCast(matched_indices[i]);
                if (index <= range_end) {
                    const next_end = index + 1;
                    if (next_end > range_end) {
                        range_end = next_end;
                    }
                    continue;
                }
                self.ptr[out_index] = .{ .col = range_start, .end_col = range_end };
                out_index += 1;
                range_start = index;
                range_end = index + 1;
            }
            self.ptr[out_index] = .{ .col = range_start, .end_col = range_end };
            out_index += 1;
            return @intCast(out_index);
        } else if (@bitSizeOf(usize) == 32) {
            // Otherwise, we write the highlight ranges from the back to avoid
            // overwriting the matched character indices stored in `highlights`.
            var out_index: usize = self.capacity;
            var i: usize = matched_indices.len - 1;
            var range_start: u32 = @intCast(matched_indices[i]);
            var range_end: u32 = range_start + 1;
            while (i > 0) {
                i -= 1;
                const index: u32 = @intCast(matched_indices[i]);
                if (index + 1 >= range_start) {
                    range_start = index;
                    continue;
                }
                out_index -= 1;
                self.ptr[out_index] = .{ .col = range_start, .end_col = range_end };
                range_start = index;
                range_end = index + 1;
            }
            out_index -= 1;
            self.ptr[out_index] = .{ .col = range_start, .end_col = range_end };

            const compact_len = self.capacity - out_index;
            if (out_index != 0) {
                @memcpy(self.ptr[0..compact_len], self.ptr[out_index..][0..compact_len]);
            }
            return @intCast(compact_len);
        }
        comptime unreachable;
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
