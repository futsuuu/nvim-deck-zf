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
    const highlight_count = b: {
        const matched = zf.highlightToken(text, query, @ptrCast(highlights[0..highlight_capacity]), .{
            .filename = std.fs.path.basename(text),
        });
        // iterate with reversed order for 32-bit environment
        var i = matched.len;
        while (0 < i) {
            i -= 1;
            const index = matched[i];
            highlights[i] = .{
                .col = @intCast(index),
                .end_col = @intCast(index + 1),
            };
        }
        break :b matched.len;
    };
    return @intCast(highlight_count);
}
