pub const Error = error{
    IncompleteMap,
    IncompleteArray,
    IllegalToken,
    ExpectedEquals,
};

pub fn parse(ally: Allocator, input: []const u8) !ElementList.Slice {
    var list = ElementList.init(ally);
    defer list.deinit();

    var path = try std.ArrayList(usize).initCapacity(ally, 16);
    defer path.deinit();

    var tokenizer = Tokenizer.init(input);
    var token = try tokenizer.next();
    try path.append(0);
    try list.append(.map, .exp);
    var slice = list.slice();
    var coll: usize = 0;
    var prev: usize = 0;

    while (true) {
        switch (slice.get_kind(coll)) {
            .map, .tmap => switch (token.tag) {
                .end => switch (path.items.len) {
                    1 => {
                        slice.alter_flag(coll, prev, .del_all);
                        break;
                    },
                    else => return Error.IncompleteMap,
                },
                .eql, .arr_end => return Error.IllegalToken,
                .sep => slice.alter_flag(coll, prev, .add_sep),
                .gap => slice.alter_flag(coll, prev, .add_gap),
                .com => {
                    slice.alter_flag(coll, prev, .del_sep);
                    prev = list.len;
                    try list.append(.com, .exp);
                    // reslice
                    slice = list.slice();
                    slice.grow_by(coll, 1);
                    slice.set_source(prev, token.src);
                    slice.expand(coll, prev);
                },
                .map_end => {
                    slice.alter_flag(coll, prev, .del_all);
                    prev = coll;
                    _ = path.pop();
                    coll = path.getLastOrNull() orelse return Error.IllegalToken;
                    slice.expand(coll, prev);
                    slice.grow_by(coll, slice.get_size(prev));
                },
                else => {
                    coll = list.len;
                    prev = coll;
                    try path.append(coll);
                    try list.append(.kv, .inl);
                    // reslice
                    slice = list.slice();
                    continue;
                },
            },
            .kv => switch (slice.kv_state(coll)) {
                .empty, .eql => switch (token.tag) {
                    .end => return Error.IncompleteMap,
                    .com, .eql, .map_end, .arr_end => return Error.IllegalToken,
                    .sep, .gap => {},
                    inline .sym, .num, .esc, .raw => |tag| {
                        prev = list.len;
                        switch (tag) {
                            .sym => try list.append(.sym, .inl),
                            .num => try list.append(.num, .inl),
                            .esc => try list.append(.esc, .inl),
                            .raw => try list.append(.raw, .exp),
                            else => {},
                        }
                        // reslice
                        slice = list.slice();
                        if (tag == .raw) slice.expand(coll, prev);
                        slice.grow_by(coll, 1);
                        slice.set_source(prev, token.src);
                    },
                    inline .map, .map_tag, .arr, .arr_tag => |tag| {
                        coll = list.len;
                        prev = coll;
                        try path.append(coll);
                        switch (tag) {
                            .map => try list.append(.map, .inl),
                            .map_tag => {
                                try list.append(.tmap, .inl);
                                try list.append(.sym, .inl);
                            },
                            .arr => try list.append(.arr, .inl),
                            .arr_tag => {
                                try list.append(.tarr, .inl);
                                try list.append(.sym, .inl);
                            },
                            else => {},
                        }
                        // reslice
                        slice = list.slice();
                        if (tag == .map_tag or tag == .arr_tag) {
                            slice.grow_by(coll, 1);
                            slice.set_source(coll + 1, token.src[0..(token.src.len - 1)]);
                        }
                    },
                },
                .key => switch (token.tag) {
                    .sep, .gap => {},
                    .eql => slice.grow_by(coll, 1),
                    else => return Error.ExpectedEquals,
                },
                .val => {
                    prev = coll;
                    _ = path.pop();
                    coll = path.getLast();
                    slice.expand(coll, prev);
                    slice.grow_by(coll, slice.get_size(prev));
                    continue; // don't move to next token
                },
            },
            .arr, .tarr => switch (token.tag) {
                .end => return Error.IncompleteArray,
                .eql, .map_end => return Error.IllegalToken,
                .sep => slice.alter_flag(coll, prev, .add_sep),
                .gap => slice.alter_flag(coll, prev, .add_gap),
                .com => {
                    prev = list.len;
                    try list.append(.com, .exp);
                    // reslice
                    slice = list.slice();
                    slice.alter_flag(coll, prev - 1, .del_sep);
                    slice.grow_by(coll, 1);
                    slice.set_source(prev, token.src);
                    slice.expand(coll, prev);
                },
                .arr_end => {
                    slice.alter_flag(coll, prev, .del_all);
                    prev = coll;
                    _ = path.pop();
                    coll = path.getLast();
                    slice.expand(coll, prev);
                    slice.grow_by(coll, slice.get_size(prev));
                },
                inline .sym, .num, .esc, .raw => |tag| {
                    prev = list.len;
                    switch (tag) {
                        .sym => try list.append(.sym, .inl),
                        .num => try list.append(.num, .inl),
                        .esc => try list.append(.esc, .inl),
                        .raw => try list.append(.raw, .exp),
                        else => {},
                    }
                    // reslice
                    slice = list.slice();
                    if (tag == .raw) slice.expand(coll, prev);
                    slice.grow_by(coll, 1);
                    slice.set_source(prev, token.src);
                },
                inline .map, .map_tag, .arr, .arr_tag => |tag| {
                    coll = list.len;
                    prev = coll;
                    try path.append(coll);
                    switch (tag) {
                        .map => try list.append(.map, .inl),
                        .map_tag => {
                            try list.append(.tmap, .inl);
                            try list.append(.sym, .inl);
                        },
                        .arr => try list.append(.arr, .inl),
                        .arr_tag => {
                            try list.append(.tarr, .inl);
                            try list.append(.sym, .inl);
                        },
                        else => {},
                    }
                    // reslice
                    slice = list.slice();
                    if (tag == .map_tag or tag == .arr_tag) {
                        slice.grow_by(coll, 1);
                        slice.set_source(coll + 1, token.src[0..(token.src.len - 1)]);
                    }
                },
            },
            else => unreachable,
        }

        token = try tokenizer.next();
    }

    return list.to_owned_slice();
}

pub fn main() !void {
    var stdin = std.io.bufferedReader(std.io.getStdIn().reader());
    var stdout = std.io.bufferedWriter(std.io.getStdOut().writer());
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();
    const input = try stdin.reader().readAllAlloc(gpa, 1024 * 1000);
    defer gpa.free(input);
    var tree = try parse(gpa, input);
    defer tree.deinit(gpa);
    try tree.write(gpa, stdout.writer());
    try stdout.flush();
}

test "empty" {
    try test_elements("", &.{.{ .kind = .map, .flag = .exp }});
    try test_elements(", ,\t\t \n\r\n,\n  ,", &.{.{ .kind = .map, .flag = .exp }});
}

test "comments" {
    try test_elements(
        \\#
        \\,
        \\
        \\ #
        \\
        \\,#
    , &.{
        .{ .kind = .map, .flag = .exp },
        .{ .kind = .com, .flag = .exp_gap },
        .{ .kind = .com, .flag = .exp_gap },
        .{ .kind = .com, .flag = .exp },
    });
}

test "collection errors" {
    try std.testing.expectError(Error.IllegalToken, test_elements("=", &.{}));
    try std.testing.expectError(Error.IllegalToken, test_elements("]", &.{}));
    try std.testing.expectError(Error.IllegalToken, test_elements(")", &.{}));
    try std.testing.expectError(Error.IncompleteMap, test_elements("[(", &.{}));
    try std.testing.expectError(Error.ExpectedEquals, test_elements("()", &.{}));
    try std.testing.expectError(Error.ExpectedEquals, test_elements("42", &.{}));
    try std.testing.expectError(Error.IncompleteMap, test_elements("(), =", &.{}));
    try std.testing.expectError(Error.IncompleteArray, test_elements("([", &.{}));
}

test "inline kv pairs" {
    try test_elements(
        \\a=1,b=,2 c = 3,
        \\
        \\d=
        \\  4,
        \\#
        \\
        \\d=5
    , &.{
        .{ .kind = .map, .flag = .exp },
        .{ .kind = .kv, .flag = .inl_sep },
        .{ .kind = .sym, .flag = .inl },
        .{ .kind = .num, .flag = .inl },
        .{ .kind = .kv, .flag = .inl },
        .{ .kind = .sym, .flag = .inl },
        .{ .kind = .num, .flag = .inl },
        .{ .kind = .kv, .flag = .inl_sep },
        .{ .kind = .sym, .flag = .inl },
        .{ .kind = .num, .flag = .inl },
        .{ .kind = .kv, .flag = .inl },
        .{ .kind = .sym, .flag = .inl },
        .{ .kind = .num, .flag = .inl },
        .{ .kind = .com, .flag = .exp_gap },
        .{ .kind = .kv, .flag = .inl },
        .{ .kind = .sym, .flag = .inl },
        .{ .kind = .num, .flag = .inl },
    });
}

test "inline array" {
    try test_elements(
        \\a=[1,2
        \\
        \\    3 4]
    , &.{
        .{ .kind = .map, .flag = .exp },
        .{ .kind = .kv, .flag = .inl },
        .{ .kind = .sym, .flag = .inl },
        .{ .kind = .arr, .flag = .inl },
        .{ .kind = .num, .flag = .inl_sep },
        .{ .kind = .num, .flag = .inl_gap },
        .{ .kind = .num, .flag = .inl },
        .{ .kind = .num, .flag = .inl },
    });
}

test "nested example 1" {
    try test_elements(
        \\a=([]=1, "b"=()), c=d
    , &.{
        .{ .kind = .map, .flag = .exp },
        .{ .kind = .kv, .flag = .inl_sep },
        .{ .kind = .sym, .flag = .inl },
        .{ .kind = .map, .flag = .inl },
        .{ .kind = .kv, .flag = .inl_sep },
        .{ .kind = .arr, .flag = .inl },
        .{ .kind = .num, .flag = .inl },
        .{ .kind = .kv, .flag = .inl },
        .{ .kind = .esc, .flag = .inl },
        .{ .kind = .map, .flag = .inl },
        .{ .kind = .kv, .flag = .inl },
        .{ .kind = .sym, .flag = .inl },
        .{ .kind = .sym, .flag = .inl },
    });
}

test "output example" {
    const ally = std.testing.allocator;
    var tree = try parse(ally,
        \\a=tag[ #
        \\1,2
        \\
        \\"three"
        \\
        \\], b=[]
        \\
        \\| a
        \\,, = | b
        \\ | c
        \\|d
        \\c=(1=2 3=4 5=|6
        \\|6b
        \\
        \\|7
        \\  | SEVEN
        \\  = |8
        \\ | EIGHT
        \\
        \\
        \\ # even
        \\ # more
        \\    # nesting
        \\nest = [(
        \\a=b, |9
        \\= "done", |a
        \\= |b
        \\)]
        \\)
        \\d=[1,2
        \\
        \\3], #done
    );
    defer tree.deinit(ally);
    var list = std.ArrayList(u8).init(ally);
    defer list.deinit();
    try tree.write(ally, list.writer());
    try std.testing.expectEqualStrings(
        \\a = tag[
        \\	#
        \\	1, 2
        \\
        \\	"three"
        \\], b = []
        \\
        \\| a
        \\=
        \\| b
        \\| c
        \\|d
        \\c = (
        \\	1 = 2
        \\	3 = 4
        \\	5 =
        \\	|6
        \\	|6b
        \\
        \\	|7
        \\	| SEVEN
        \\	=
        \\	|8
        \\	| EIGHT
        \\
        \\	# even
        \\	# more
        \\	# nesting
        \\	nest = [
        \\		(
        \\			a = b
        \\			|9
        \\			= "done"
        \\			|a
        \\			=
        \\			|b
        \\		)
        \\	]
        \\)
        \\d = [1, 2, 3]
        \\#done
        \\
    , list.items);
}

const TestInput = struct {
    kind: ElementList.Kind,
    flag: ElementList.Flag,
};

fn test_elements(input: []const u8, els: []const TestInput) !void {
    const ally = std.testing.allocator;
    var tree = try parse(ally, input);
    defer tree.deinit(ally);
    try std.testing.expectEqual(tree.elements.len, els.len);
    for (els, 0..) |el, i| {
        // TODO size checks
        try std.testing.expectEqual(el.kind, tree.get_kind(i));
        try std.testing.expectEqual(el.flag, tree.get_flag(i));
    }
}

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Tokenizer = @import("tokenizer.zig");
const ElementList = @import("element_list.zig");
