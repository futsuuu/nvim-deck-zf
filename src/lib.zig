const std = @import("std");
const zf = @import("zf");

export fn deck_zf_match(
    buf: [*]const u8,
    query_len: u32,
    text_len: u32,
) f64 {
    const query = buf[0..query_len];
    const text = buf[query_len..][0..text_len];
    const rank = zf.rankToken(text, query, .{
        .filename = std.fs.path.basename(text),
    }) orelse {
        return 0;
    };
    if (rank < 0) {
        return 0;
    }
    return 1 / (rank + 1);
}

const Highlight = extern struct {
    col: u32 align(@sizeOf(u64)),
    end_col: u32,
};

export fn deck_zf_decor(
    buf: [*]const u8,
    query_len: u32,
    text_len: u32,
    highlights: [*]Highlight,
    highlight_capacity: u32,
) u32 {
    const query = buf[0..query_len];
    const text = buf[query_len..][0..text_len];
    // the matched character indices stored in `highlights`
    const matched = zf.highlightToken(text, query, @ptrCast(highlights[0..highlight_capacity]), .{
        .filename = std.fs.path.basename(text),
    });
    if (matched.len == 0) {
        return 0;
    }

    comptime std.debug.assert(@bitSizeOf(Highlight) == 64);
    switch (@bitSizeOf(usize)) {
        // When the size of `Highlight` matches `usize`, we can read the
        // matched character indices (`[]usize`) from the front and write the
        // highlight ranges (`[]Highlight`) from the front simultaneously.
        64 => {
            var out_index: usize = 0;
            var range_start: u32 = @intCast(matched[0]);
            var range_end: u32 = range_start + 1;
            var i: usize = 1;
            while (i < matched.len) : (i += 1) {
                const index: u32 = @intCast(matched[i]);
                if (index <= range_end) {
                    const next_end = index + 1;
                    if (next_end > range_end) {
                        range_end = next_end;
                    }
                    continue;
                }
                highlights[out_index] = .{ .col = range_start, .end_col = range_end };
                out_index += 1;
                range_start = index;
                range_end = index + 1;
            }
            highlights[out_index] = .{ .col = range_start, .end_col = range_end };
            out_index += 1;
            return @intCast(out_index);
        },
        // Otherwise, we write the highlight ranges from the back to avoid
        // overwriting the matched character indices stored in `highlights`.
        32 => {
            var out_index: usize = highlight_capacity;
            var i: usize = matched.len - 1;
            var range_start: u32 = @intCast(matched[i]);
            var range_end: u32 = range_start + 1;
            while (i > 0) {
                i -= 1;
                const index: u32 = @intCast(matched[i]);
                if (index + 1 >= range_start) {
                    range_start = index;
                    continue;
                }
                out_index -= 1;
                highlights[out_index] = .{ .col = range_start, .end_col = range_end };
                range_start = index;
                range_end = index + 1;
            }
            out_index -= 1;
            highlights[out_index] = .{ .col = range_start, .end_col = range_end };

            const compact_len = highlight_capacity - out_index;
            if (out_index != 0) {
                @memcpy(highlights[0..compact_len], highlights[out_index..][0..compact_len]);
            }
            return @intCast(compact_len);
        },
        else => unreachable,
    }
}

test "deck_zf_decor merges adjacent highlights" {
    const query = "abc";
    const text = "abc";
    const buf = query ++ text;

    var highlights: [query.len]Highlight = undefined;
    const count = deck_zf_decor(buf, query.len, text.len, &highlights, highlights.len);

    try std.testing.expectEqual(1, count);
    try std.testing.expectEqual(Highlight{ .col = 0, .end_col = 3 }, highlights[0]);
}

test "deck_zf_decor keeps separated highlights" {
    const query = "ac";
    const text = "abc";
    const buf = query ++ text;

    var highlights: [query.len]Highlight = undefined;
    const count = deck_zf_decor(buf, query.len, text.len, &highlights, highlights.len);

    try std.testing.expectEqual(2, count);
    try std.testing.expectEqual(Highlight{ .col = 0, .end_col = 1 }, highlights[0]);
    try std.testing.expectEqual(Highlight{ .col = 2, .end_col = 3 }, highlights[1]);
}

test "deck_zf_decor returns zero when query not found" {
    const query = "xyz";
    const text = "abc";
    const buf = query ++ text;

    var highlights: [query.len]Highlight = undefined;
    const count = deck_zf_decor(buf, query.len, text.len, &highlights, highlights.len);

    try std.testing.expectEqual(0, count);
}

test "deck_zf_decor highlights match at end" {
    const query = "de";
    const text = "abcde";
    const buf = query ++ text;

    var highlights: [query.len]Highlight = undefined;
    const count = deck_zf_decor(buf, query.len, text.len, &highlights, highlights.len);

    try std.testing.expectEqual(1, count);
    try std.testing.expectEqual(Highlight{ .col = 3, .end_col = 5 }, highlights[0]);
}

test "deck_zf_decor keeps multiple separated ranges" {
    const query = "bdf";
    const text = "abcdef";
    const buf = query ++ text;

    var highlights: [query.len]Highlight = undefined;
    const count = deck_zf_decor(buf, query.len, text.len, &highlights, highlights.len);

    try std.testing.expectEqual(3, count);
    try std.testing.expectEqual(Highlight{ .col = 1, .end_col = 2 }, highlights[0]);
    try std.testing.expectEqual(Highlight{ .col = 3, .end_col = 4 }, highlights[1]);
    try std.testing.expectEqual(Highlight{ .col = 5, .end_col = 6 }, highlights[2]);
}
