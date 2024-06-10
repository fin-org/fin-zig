// inspired by zigs own tokenizer.
// - The tokenizers job is to segment the input into tokens for further processing (AST).
// - Tokens have a tag (type) and a slice into the input
// - The tokenizer does not guarantee tokens are valid (spec-compliant) it will only do
// enough validation to classify them.

const std = @import("std");

pub const Token = struct {
    src: []const u8,
    tag: Tag,

    pub const Tag = enum {
        symbol,
        number,
        esc_string,
        raw_string,
        comment,
        comma,
        equals,
        left_paren,
        right_paren,
        left_bracket,
        right_bracket,
    };
};

pub const Tokenizer = struct {
    input: []const u8,
    index: usize,
    line: usize,

    pub const State = enum {
        init,
        sym,
        num,
        num_exp,
        esc_str,
        esc_seq,
        esc_uni,
        esc_uni_hex,
        raw_str,
        raw_str_alt,
        com,
        com_alt,
    };

    pub const Error = error{
        IllegalCodepoint,
        IllegalEscape,
        UnterminatedString,
        UnescapedControlCode,
        EndOfInput,
    };

    pub fn init(input: []const u8) Tokenizer {
        const has_bom = std.mem.startsWith(u8, input, "\xEF\xBB\xBF");
        return .{ .index = if (has_bom) 3 else 0, .input = input, .line = 0 };
    }

    pub fn next(self: *Tokenizer) !Token {
        var state: State = .init;
        var c: u8 = 0;
        var start: usize = self.index;
        while (true) : (self.index += 1) {
            if (self.index >= self.input.len) {
                switch (state) {
                    .init => return Error.EndOfInput,
                    .esc_str, .esc_seq, .esc_uni => return Error.UnterminatedString,
                    else => c = '\n',
                }
                self.index = self.input.len;
            } else c = self.input[self.index];
            if (c == '\n') self.line += 1;
            switch (state) {
                .init => switch (c) {
                    ' ', '\t', '\r', '\n' => {
                        start += 1;
                        continue;
                    },
                    ',' => {
                        self.index += 1;
                        return .{ .tag = .comma, .src = self.input[start..self.index] };
                    },
                    '=' => {
                        self.index += 1;
                        return .{ .tag = .equals, .src = self.input[start..self.index] };
                    },
                    '(' => {
                        self.index += 1;
                        return .{ .tag = .left_paren, .src = self.input[start..self.index] };
                    },
                    ')' => {
                        self.index += 1;
                        return .{ .tag = .right_paren, .src = self.input[start..self.index] };
                    },
                    '[' => {
                        self.index += 1;
                        return .{ .tag = .left_bracket, .src = self.input[start..self.index] };
                    },
                    ']' => {
                        self.index += 1;
                        return .{ .tag = .right_bracket, .src = self.input[start..self.index] };
                    },
                    ':', '_', 'a'...'z' => state = .sym,
                    '-', '0'...'9' => state = .num,
                    '"' => state = .esc_str,
                    '|' => state = .raw_str,
                    '#' => state = .com,
                    else => return Error.IllegalCodepoint,
                },
                .sym => switch (c) {
                    ':', '_', 'a'...'z', '0'...'9' => continue,
                    else => return .{ .tag = .symbol, .src = self.input[start..self.index] },
                },
                .num => switch (c) {
                    '.', '-', '0'...'9' => continue,
                    'e' => state = .num_exp,
                    else => return .{ .tag = .number, .src = self.input[start..self.index] },
                },
                .num_exp => switch (c) {
                    '.', '-', '0'...'9' => continue,
                    else => return .{ .tag = .number, .src = self.input[start..self.index] },
                },
                .esc_str => switch (c) {
                    '\\' => state = .esc_seq,
                    '"' => {
                        self.index += 1;
                        return .{ .tag = .esc_string, .src = self.input[start..self.index] };
                    },
                    else => {
                        if (c < 32) return Error.UnescapedControlCode;
                        continue;
                    },
                },
                .esc_seq => switch (c) {
                    '\\', '"', 'r', 'n', 't' => state = .esc_str,
                    'u' => state = .esc_uni,
                    else => return Error.IllegalEscape,
                },
                .esc_uni => switch (c) {
                    '{' => state = .esc_uni_hex,
                    else => return Error.IllegalEscape,
                },
                .esc_uni_hex => switch (c) {
                    '0'...'9', 'a'...'f' => continue,
                    '}' => state = .esc_str,
                    else => return Error.IllegalEscape,
                },
                .raw_str => switch (c) {
                    '\n' => state = .raw_str_alt,
                    else => continue,
                },
                .raw_str_alt => switch (c) {
                    '|' => state = .raw_str,
                    ' ', '\t' => continue,
                    else => return .{ .tag = .raw_string, .src = self.input[start..self.index] },
                },
                .com => switch (c) {
                    '\n' => state = .com_alt,
                    else => continue,
                },
                .com_alt => switch (c) {
                    '#' => state = .com,
                    ' ', '\t' => continue,
                    else => return .{ .tag = .comment, .src = self.input[start..self.index] },
                },
            }
        }
    }
};

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
        const token = tokenizer.next() catch |err| switch (err) {
            Tokenizer.Error.EndOfInput => break,
            else => return err,
        };
        try stdout_w.print("--- {s}\n", .{@tagName(token.tag)});
        switch (token.tag) {
            .symbol,
            .number,
            .esc_string,
            .raw_string,
            .comment,
            => try stdout_w.print("{s}\n", .{token.src}),
            else => {},
        }
    }
    try stdout.flush();
}

test "single codepoint tokens" {
    try test_tokens("\xEF\xBB\xBF , \t \n = [( )]\r\n", &.{
        .{ .tag = .comma, .src = "," },
        .{ .tag = .equals, .src = "=" },
        .{ .tag = .left_bracket, .src = "[" },
        .{ .tag = .left_paren, .src = "(" },
        .{ .tag = .right_paren, .src = ")" },
        .{ .tag = .right_bracket, .src = "]" },
    }, Tokenizer.Error.EndOfInput);
}

test "illegal codepoints" {
    try test_tokens(" \r A", &.{}, Tokenizer.Error.IllegalCodepoint);
    try test_tokens("=>", &.{
        .{ .tag = .equals, .src = "=" },
    }, Tokenizer.Error.IllegalCodepoint);
}

test "symbols" {
    try test_tokens(" a _ : a1::__:", &.{
        .{ .tag = .symbol, .src = "a" },
        .{ .tag = .symbol, .src = "_" },
        .{ .tag = .symbol, .src = ":" },
        .{ .tag = .symbol, .src = "a1::__:" },
    }, Tokenizer.Error.EndOfInput);
}

test "numbers" {
    try test_tokens("1 -0.0 1.23e45e2", &.{
        .{ .tag = .number, .src = "1" },
        .{ .tag = .number, .src = "-0.0" },
        .{ .tag = .number, .src = "1.23e45" },
        .{ .tag = .symbol, .src = "e2" },
    }, Tokenizer.Error.EndOfInput);
}

test "escaped strings" {
    try test_tokens(
        \\ "a" "\r\n\t\"\\\u{}" "a\u{01fe32}b"
    , &.{
        .{ .tag = .esc_string, .src = 
        \\"a"
        },
        .{ .tag = .esc_string, .src = 
        \\"\r\n\t\"\\\u{}"
        },
        .{ .tag = .esc_string, .src = 
        \\"a\u{01fe32}b"
        },
    }, Tokenizer.Error.EndOfInput);
}

test "illegal strings" {
    try test_tokens(
        \\"\"
    , &.{}, Tokenizer.Error.UnterminatedString);
    try test_tokens(
        \\"\{}"
    , &.{}, Tokenizer.Error.IllegalEscape);
    try test_tokens(
        \\"\ua"
    , &.{}, Tokenizer.Error.IllegalEscape);
    try test_tokens(
        \\"\u{ }"
    , &.{}, Tokenizer.Error.IllegalEscape);
}

test "raw strings" {
    try test_tokens(
        \\|
        \\
        \\ |a
        \\ |b|
    , &.{
        .{ .tag = .raw_string, .src = "|\n" },
        .{ .tag = .raw_string, .src = "|a\n |b|" },
    }, Tokenizer.Error.EndOfInput);
}

test "comments" {
    try test_tokens(
        \\ ##
        \\
        \\ #|
        \\  #\n
    , &.{
        .{ .tag = .comment, .src = "##\n" },
        .{ .tag = .comment, .src = "#|\n  #\\n" },
    }, Tokenizer.Error.EndOfInput);
}

fn test_tokens(input: []const u8, expected_tokens: []const Token, err: anyerror) !void {
    var tokenizer = Tokenizer.init(input);
    for (expected_tokens) |expected_token| {
        const token = try tokenizer.next();
        try std.testing.expectEqual(expected_token.tag, token.tag);
        try std.testing.expectEqualStrings(expected_token.src, token.src);
    }
    try std.testing.expectError(err, tokenizer.next());
}
