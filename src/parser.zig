pub const Error = error{
    IncompleteMap,
    IncompleteArray,
    IllegalToken,
    IllegalMapEnd,
    IllegalArrayEnd,
    IllegalEquals,
    ExpectedEquals,
};

pub fn parse(ally: Allocator, input: []const u8) !ElementList.Slice {
    var list = ElementList.init(ally);
    defer list.deinit();

    var path = std.ArrayList(usize).init(ally);
    defer path.deinit();

    var tokenizer = Tokenizer.init(input);
    var token = try tokenizer.next();
    try path.append(0);
    try list.append(.map, .exp);
    var slice = list.slice();
    var coll: usize = 0;
    var prev: usize = 0;

    while (true) {
        // std.debug.print("{} {} {s}\n", .{ coll, prev, @tagName(token.tag) });
        switch (slice.get_kind(coll)) {
            .map, .tmap => switch (token.tag) {
                .end => switch (path.items.len) {
                    1 => {
                        slice.alter_flag(coll, prev, .del_all);
                        break;
                    },
                    else => return Error.IncompleteMap,
                },
                .eql => return Error.IllegalEquals,
                .arr_end => return Error.IllegalArrayEnd,
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
                .map_end => {
                    slice.alter_flag(coll, prev, .del_all);
                    prev = coll;
                    _ = path.pop();
                    coll = path.getLastOrNull() orelse return Error.IllegalMapEnd;
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
                .eql => return Error.IllegalEquals,
                .map_end => return Error.IllegalMapEnd,
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
                // duplicated above this is just accepting a value
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

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Tokenizer = @import("tokenizer.zig");
const ElementList = @import("element_list.zig");

// TODO. write tests!

test "comments" {
    const ally = std.testing.allocator;
    var tree = try parse(ally,
        \\#
        \\ a = [1 2 
        \\
        \\ 3,,,,
        \\ |raw
        \\]
        \\
    );
    defer tree.deinit(ally);

    for (0..tree.elements.len) |i| {
        const el = tree.elements.get(i);

        switch (el.kind) {
            .kv, .map, .tmap, .arr, .tarr => {
                std.debug.print("{s} {s} ({})\n", .{
                    @tagName(el.kind),
                    @tagName(el.flag),
                    tree.sizes[el.index],
                });
            },
            else => std.debug.print("{s} {s}\n", .{
                @tagName(el.kind),
                @tagName(el.flag),
            }),
        }
    }
}
