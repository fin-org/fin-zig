input: []const u8,
index: usize,

pub const Token = struct { src: []const u8, tag: Tag };

pub const Tag = enum {
    sym,
    num,
    esc,
    raw,
    com,
    sep,
    gap,
    eql,
    map,
    map_tag,
    map_end,
    arr,
    arr_tag,
    arr_end,
    end,
};

const State = enum {
    init,
    gap,
    sym,
    num,
    num_exp,
    esc,
    esc_seq,
    esc_uni,
    esc_uni_hex,
    raw,
    raw_alt,
    com,
    com_alt,
};

pub const Error = error{
    IllegalCodepoint,
    IllegalEscape,
    UnterminatedString,
    UnescapedControlCode,
};

pub fn init(input: []const u8) Tokenizer {
    const has_bom = std.mem.startsWith(u8, input, "\xEF\xBB\xBF");
    return .{ .index = if (has_bom) 3 else 0, .input = input };
}

pub fn next(self: *Tokenizer) !Token {
    var state: State = .init;
    var c: u8 = 0;
    var start = self.index;
    var end = self.index;
    while (true) : (self.index += 1) {
        if (self.index >= self.input.len) {
            self.index = self.input.len;
            switch (state) {
                .init, .gap => return .{ .tag = .end, .src = self.input[self.index..self.index] },
                .esc, .esc_seq, .esc_uni, .esc_uni_hex => return Error.UnterminatedString,
                else => c = '\n',
            }
        } else c = self.input[self.index];
        switch (state) {
            .init => switch (c) {
                ' ', '\t', '\r' => start += 1,
                ',' => {
                    self.index += 1;
                    return .{ .tag = .sep, .src = self.input[start..self.index] };
                },
                '=' => {
                    self.index += 1;
                    return .{ .tag = .eql, .src = self.input[start..self.index] };
                },
                '(' => {
                    self.index += 1;
                    return .{ .tag = .map, .src = self.input[start..self.index] };
                },
                ')' => {
                    self.index += 1;
                    return .{ .tag = .map_end, .src = self.input[start..self.index] };
                },
                '[' => {
                    self.index += 1;
                    return .{ .tag = .arr, .src = self.input[start..self.index] };
                },
                ']' => {
                    self.index += 1;
                    return .{ .tag = .arr_end, .src = self.input[start..self.index] };
                },
                '\n' => state = .gap,
                ':', '_', 'a'...'z' => state = .sym,
                '-', '0'...'9' => state = .num,
                '"' => state = .esc,
                '|' => state = .raw,
                '#' => state = .com,
                else => return Error.IllegalCodepoint,
            },
            .gap => switch (c) {
                ' ', '\t', '\r' => {},
                '\n' => {
                    self.index += 1;
                    return .{ .tag = .gap, .src = self.input[start..self.index] };
                },
                else => {
                    start = self.index;
                    self.index -= 1;
                    state = .init;
                },
            },
            .sym => switch (c) {
                ':', '_', 'a'...'z', '0'...'9' => {},
                '[' => {
                    self.index += 1;
                    return .{ .tag = .arr_tag, .src = self.input[start..self.index] };
                },
                '(' => {
                    self.index += 1;
                    return .{ .tag = .map_tag, .src = self.input[start..self.index] };
                },
                else => return .{ .tag = .sym, .src = self.input[start..self.index] },
            },
            .num => switch (c) {
                '.', '-', '0'...'9' => {},
                'e' => state = .num_exp,
                else => return .{ .tag = .num, .src = self.input[start..self.index] },
            },
            .num_exp => switch (c) {
                '.', '-', '0'...'9' => {},
                else => return .{ .tag = .num, .src = self.input[start..self.index] },
            },
            .esc => switch (c) {
                '\\' => state = .esc_seq,
                '"' => {
                    self.index += 1;
                    return .{ .tag = .esc, .src = self.input[start..self.index] };
                },
                else => if (c < 32) return Error.UnescapedControlCode,
            },
            .esc_seq => switch (c) {
                '\\', '"', 'r', 'n', 't' => state = .esc,
                'u' => state = .esc_uni,
                else => return Error.IllegalEscape,
            },
            .esc_uni => switch (c) {
                '{' => state = .esc_uni_hex,
                else => return Error.IllegalEscape,
            },
            .esc_uni_hex => switch (c) {
                '0'...'9', 'a'...'f' => {},
                '}' => state = .esc,
                else => return Error.IllegalEscape,
            },
            .raw => switch (c) {
                '\n' => {
                    state = .raw_alt;
                    end = self.index;
                },
                else => {},
            },
            .raw_alt => switch (c) {
                '|' => state = .raw,
                ' ', '\t' => {},
                else => {
                    self.index = end;
                    return .{ .tag = .raw, .src = self.input[start..end] };
                },
            },
            .com => switch (c) {
                '\n' => {
                    state = .com_alt;
                    end = self.index;
                },
                else => {},
            },
            .com_alt => switch (c) {
                '#' => state = .com,
                ' ', '\t' => {},
                else => {
                    self.index = end;
                    return .{ .tag = .com, .src = self.input[start..end] };
                },
            },
        }
    }
}

pub fn main() !void {
    var stdin = std.io.bufferedReader(std.io.getStdIn().reader());
    var stdout = std.io.bufferedWriter(std.io.getStdOut().writer());
    var stdout_w = stdout.writer();
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();
    const input = try stdin.reader().readAllAlloc(gpa, 1024 * 1000);
    defer gpa.free(input);
    var tokenizer = Tokenizer.init(input);
    while (true) {
        const token = try tokenizer.next();
        switch (token.tag) {
            .end => break,
            else => try stdout_w.print("--- {s}\n", .{@tagName(token.tag)}),
        }
        switch (token.tag) {
            .sym,
            .num,
            .esc,
            .raw,
            .com,
            .map_tag,
            .arr_tag,
            => try stdout_w.print("{s}\n", .{token.src}),
            else => {},
        }
    }
    try stdout.flush();
}

test "comma, equals and gaps" {
    try test_tokens("\xEF\xBB\xBF , \t \n = \n\r\n\n \n\n", &.{
        .{ .tag = .sep, .src = "," },
        .{ .tag = .eql, .src = "=" },
        .{ .tag = .gap, .src = "\n\r\n" },
        .{ .tag = .gap, .src = "\n \n" },
        .{ .tag = .end, .src = "" },
    });
}

test "maps and arrs" {
    try test_tokens("\t \n [( )]\ta(\n\t\n\nb[ ])\r\n", &.{
        .{ .tag = .arr, .src = "[" },
        .{ .tag = .map, .src = "(" },
        .{ .tag = .map_end, .src = ")" },
        .{ .tag = .arr_end, .src = "]" },
        .{ .tag = .map_tag, .src = "a(" },
        .{ .tag = .gap, .src = "\n\t\n" },
        .{ .tag = .arr_tag, .src = "b[" },
        .{ .tag = .arr_end, .src = "]" },
        .{ .tag = .map_end, .src = ")" },
        .{ .tag = .end, .src = "" },
    });
}

test "illegal codepoints" {
    try std.testing.expectError(
        Error.IllegalCodepoint,
        test_tokens(" \r A", &.{
            .{ .tag = .end, .src = "" },
        }),
    );
    try std.testing.expectError(
        Error.IllegalCodepoint,
        test_tokens("=>", &.{
            .{ .tag = .eql, .src = "=" },
            .{ .tag = .end, .src = "" },
        }),
    );
}

test "syms" {
    try test_tokens(" a _ : a1::__:", &.{
        .{ .tag = .sym, .src = "a" },
        .{ .tag = .sym, .src = "_" },
        .{ .tag = .sym, .src = ":" },
        .{ .tag = .sym, .src = "a1::__:" },
        .{ .tag = .end, .src = "" },
    });
}

test "nums" {
    try test_tokens("1 -0.0 1.23e45e2", &.{
        .{ .tag = .num, .src = "1" },
        .{ .tag = .num, .src = "-0.0" },
        .{ .tag = .num, .src = "1.23e45" },
        .{ .tag = .sym, .src = "e2" },
        .{ .tag = .end, .src = "" },
    });
}

test "escaped strings" {
    try test_tokens(
        \\ "a" "\r\n\t\"\\\u{}" "a\u{01fe32}b"
    , &.{
        .{ .tag = .esc, .src = 
        \\"a"
        },
        .{ .tag = .esc, .src = 
        \\"\r\n\t\"\\\u{}"
        },
        .{ .tag = .esc, .src = 
        \\"a\u{01fe32}b"
        },
        .{ .tag = .end, .src = "" },
    });
}

test "illegal strings" {
    try std.testing.expectError(Error.UnterminatedString, test_tokens(
        \\"\"
    ,
        &.{.{ .tag = .end, .src = "" }},
    ));
    try std.testing.expectError(Error.IllegalEscape, test_tokens(
        \\"\{}"
    ,
        &.{.{ .tag = .end, .src = "" }},
    ));
    try std.testing.expectError(Error.IllegalEscape, test_tokens(
        \\"\ua"
    ,
        &.{.{ .tag = .end, .src = "" }},
    ));
    try std.testing.expectError(Error.IllegalEscape, test_tokens(
        \\"\u{ }"
    ,
        &.{.{ .tag = .end, .src = "" }},
    ));
}

test "raw strings" {
    try test_tokens(
        \\|
        \\
        \\ |a
        \\ |b|
        \\  
        \\|
    , &.{
        .{ .tag = .raw, .src = "|" },
        .{ .tag = .gap, .src = "\n\n" },
        .{ .tag = .raw, .src = "|a\n |b|" },
        .{ .tag = .gap, .src = "\n  \n" },
        .{ .tag = .raw, .src = "|" },
        .{ .tag = .end, .src = "" },
    });
}

test "comments" {
    try test_tokens(
        \\ ##
        \\
        \\ #|
        \\  #\n
    , &.{
        .{ .tag = .com, .src = "##" },
        .{ .tag = .gap, .src = "\n\n" },
        .{ .tag = .com, .src = "#|\n  #\\n" },
        .{ .tag = .end, .src = "" },
    });
}

const TestInput = struct {
    tag: Tag,
    src: []const u8,
};

fn test_tokens(input: []const u8, expected_tokens: []const TestInput) !void {
    var tokenizer = Tokenizer.init(input);
    for (expected_tokens) |expected_token| {
        const token = try tokenizer.next();
        try std.testing.expectEqual(expected_token.tag, token.tag);
        try std.testing.expectEqualStrings(expected_token.src, token.src);
    }
}

const std = @import("std");
const assert = std.debug.assert;
const Tokenizer = @This();
