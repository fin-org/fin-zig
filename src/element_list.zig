ally: Allocator,
elements: std.MultiArrayList(Element),
sizes: std.ArrayListUnmanaged(u32),
sources: std.ArrayListUnmanaged([]const u8),
len: usize,

pub const Kind = enum { sym, num, esc, raw, com, kv, map, tmap, arr, tarr };
pub const Flag = enum { inl, inl_gap, inl_sep, exp, exp_gap, exp_sep };
pub const Element = struct { index: u32, kind: Kind, flag: Flag };

comptime {
    assert(@sizeOf(Element) == 8);
}

pub fn init(ally: Allocator) ElementList {
    return .{
        .ally = ally,
        .elements = .{},
        .sizes = .{},
        .sources = .{},
        .len = 0,
    };
}

pub fn deinit(self: *ElementList) void {
    self.elements.deinit(self.ally);
    self.sizes.deinit(self.ally);
    self.sources.deinit(self.ally);
    self.* = undefined;
}

pub fn append(self: *ElementList, kind: Kind, flag: Flag) !void {
    var index: u32 = 0;
    switch (kind) {
        .sym, .num, .esc, .raw, .com => {
            index = @intCast(self.sources.items.len);
            try self.sources.append(self.ally, "");
        },
        else => {
            index = @intCast(self.sizes.items.len);
            try self.sizes.append(self.ally, if (kind == .kv) 0 else 1);
        },
    }
    try self.elements.append(self.ally, .{ .index = index, .kind = kind, .flag = flag });
    self.len += 1;
}

pub fn get_kind(self: *ElementList, index: usize) Kind {
    return self.elements.items(.kind)[index];
}

// slice

pub fn slice(self: *ElementList) Slice {
    return .{
        .elements = self.elements.slice(),
        .sizes = self.sizes.items,
        .sources = self.sources.items,
    };
}

pub fn to_owned_slice(self: *ElementList) !Slice {
    return .{
        .elements = self.elements.toOwnedSlice(),
        .sizes = try self.sizes.toOwnedSlice(self.ally),
        .sources = try self.sources.toOwnedSlice(self.ally),
    };
}

pub const Slice = struct {
    elements: std.MultiArrayList(Element).Slice,
    sizes: []u32,
    sources: [][]const u8,

    pub fn deinit(self: *Slice, ally: Allocator) void {
        self.elements.deinit(ally);
        ally.free(self.sizes);
        ally.free(self.sources);
        self.* = undefined;
    }

    // kind

    pub fn get_kind(self: Slice, index: usize) Kind {
        return self.elements.items(.kind)[index];
    }

    // flag

    pub fn get_flag(self: Slice, index: usize) Flag {
        return self.elements.items(.flag)[index];
    }

    pub fn expanded(self: Slice, index: usize) bool {
        return switch (self.get_flag(index)) {
            .exp, .exp_sep, .exp_gap => true,
            else => false,
        };
    }

    pub fn expand(self: Slice, coll: usize, prev: usize) void {
        assert(prev > coll);
        const flags = self.elements.items(.flag);
        switch (flags[prev]) {
            .exp, .exp_gap, .exp_sep => {
                switch (flags[coll]) {
                    .inl => flags[coll] = .exp,
                    .inl_gap => flags[coll] = .exp_gap,
                    .inl_sep => flags[coll] = .exp_sep,
                    else => {},
                }
            },
            else => {},
        }
    }

    const Op = enum { add_gap, add_sep, del_sep, del_all };

    pub fn alter_flag(self: Slice, coll: usize, prev: usize, op: Op) void {
        if (prev == coll) return;
        assert(prev > coll);

        // can't add_sep to raw strings or comments
        const prev_kind = self.elements.items(.kind)[prev];
        if (op == .add_sep and (prev_kind == .com or prev_kind == .raw)) return;

        // alter the flag
        const flags = self.elements.items(.flag);
        const prev_flag = flags[prev];
        switch (op) {
            .add_gap => flags[prev] = switch (prev_flag) {
                .inl => .inl_gap,
                .exp => .exp_gap,
                else => prev_flag,
            },
            .add_sep => flags[prev] = switch (prev_flag) {
                .inl, .inl_gap => .inl_sep,
                .exp, .exp_gap => .exp_sep,
                else => prev_flag,
            },
            .del_sep => flags[prev] = switch (prev_flag) {
                .inl_sep => .inl,
                .exp_sep => .exp,
                else => prev_flag,
            },
            .del_all => flags[prev] = switch (prev_flag) {
                .inl_sep, .inl_gap => .inl,
                .exp_sep, .exp_gap => .exp,
                else => prev_flag,
            },
        }
    }

    // size

    pub fn get_size(self: Slice, index: usize) u32 {
        return switch (self.elements.items(.kind)[index]) {
            .sym, .num, .esc, .raw, .com => 1,
            else => self.sizes[self.elements.items(.index)[index]],
        };
    }

    pub fn grow_by(self: Slice, index: usize, size: u32) void {
        switch (self.elements.items(.kind)[index]) {
            .sym, .num, .esc, .raw, .com => unreachable,
            else => self.sizes[self.elements.items(.index)[index]] += size,
        }
    }

    // source

    pub fn get_source(self: Slice, index: usize) ?[]const u8 {
        return switch (self.elements.items(.kind)[index]) {
            .sym,
            .num,
            .esc,
            .raw,
            .com,
            => self.sources[self.elements.items(.index)[index]],
            else => null,
        };
    }

    pub fn set_source(self: Slice, index: usize, source: []const u8) void {
        switch (self.elements.items(.kind)[index]) {
            .kv, .map, .tmap, .arr, .tarr => unreachable,
            else => self.sources[self.elements.items(.index)[index]] = source,
        }
    }

    const KVState = enum { empty, key, eql, val };

    pub fn kv_state(self: Slice, index: usize) KVState {
        assert(self.elements.items(.kind)[index] == .kv);
        const size = self.sizes[self.elements.items(.index)[index]];
        if (size == 0) return .empty;
        const key_size = self.get_size(index + 1);
        switch (size - key_size) {
            0 => return .key,
            1 => return .eql,
            else => {},
        }
        const val_size = self.get_size(index + 1 + key_size);
        assert(size == 1 + key_size + val_size);
        return .val;
    }

    // output

    pub fn write(self: Slice, ally: Allocator, w: anytype) !void {
        const kinds = self.elements.items(.kind);
        const idxs = self.elements.items(.index);
        const flags = self.elements.items(.flag);
        var e: usize = 0;
        var p: usize = 0;
        var c: usize = 0;
        var f: usize = self.sizes[idxs[0]];
        var tabs: u16 = 0;
        var newline = false;
        var path = try std.ArrayList(usize).initCapacity(ally, 16);
        defer path.deinit();

        while (true) {
            if (e == f) {
                // finish collection
                if (c == 0) break;
                switch (kinds[c]) {
                    .kv => {},
                    else => |kind| {
                        tabs -= 1;
                        if (newline) {
                            try w.writeByteNTimes('\t', tabs);
                            newline = false;
                        }
                        switch (kind) {
                            .map, .tmap => try w.writeByte(')'),
                            .arr, .tarr => try w.writeByte(']'),
                            else => unreachable,
                        }
                    },
                }
                p = c;
                _ = path.pop();
                c = path.getLast();
                f = c + self.sizes[idxs[c]];
            } else {
                if (newline) try w.writeByteNTimes('\t', tabs);
                switch (kinds[e]) {
                    .sym, .num, .esc => try w.writeAll(self.sources[idxs[e]]),
                    .raw => {
                        var ignore = true;
                        for (self.sources[idxs[e]]) |b| {
                            if (ignore) switch (b) {
                                ' ', '\t' => continue,
                                '|' => ignore = false,
                                else => unreachable,
                            };
                            try w.writeByte(b);
                            if (b == '\n') {
                                ignore = true;
                                try w.writeByteNTimes('\t', tabs);
                            }
                        }
                    },
                    .com => {
                        var ignore = true;
                        for (self.sources[idxs[e]]) |b| {
                            if (ignore) switch (b) {
                                ' ', '\t' => continue,
                                '#' => ignore = false,
                                else => unreachable,
                            };
                            try w.writeByte(b);
                            if (b == '\n') {
                                ignore = true;
                                try w.writeByteNTimes('\t', tabs);
                            }
                        }
                    },
                    else => |kind| {
                        // start collection
                        c = e;
                        try path.append(c);
                        f = c + self.sizes[idxs[e]];
                        e += 1;
                        if (c == 0) continue;
                        switch (kind) {
                            .map => try w.writeByte('('),
                            .arr => try w.writeByte('['),
                            .tmap => {
                                try w.writeAll(self.sources[idxs[e]]);
                                try w.writeByte('(');
                                e += 1;
                            },
                            .tarr => {
                                try w.writeAll(self.sources[idxs[e]]);
                                try w.writeByte('[');
                                e += 1;
                            },
                            .kv => {
                                newline = false;
                                continue;
                            },
                            else => unreachable,
                        }
                        tabs += 1;
                        newline = switch (flags[c]) {
                            .exp, .exp_sep, .exp_gap => true,
                            else => false,
                        };
                        if (newline) try w.writeByte('\n');
                        continue;
                    },
                }
                p = e;
                e += 1;
            }

            if (kinds[c] == .kv) {
                if (c == (p - 1)) {
                    if (kinds[p] == .raw) {
                        try w.writeByte('\n');
                        try w.writeByteNTimes('\t', tabs);
                    } else {
                        try w.writeByte(' ');
                    }
                    try w.writeByte('=');
                    if (kinds[e] == .raw) {
                        try w.writeByte('\n');
                        try w.writeByteNTimes('\t', tabs);
                    } else {
                        try w.writeByte(' ');
                    }
                }
            } else switch (flags[c]) {
                .exp, .exp_sep, .exp_gap => switch (flags[p]) {
                    .inl_gap, .exp_gap => {
                        try w.writeByteNTimes('\n', 2);
                        newline = true;
                    },
                    .inl_sep, .exp_sep => {
                        if (kinds[e] == .kv and kinds[e + 1] == .raw) {
                            try w.writeByte('\n');
                            newline = true;
                        } else {
                            try w.writeAll(", ");
                            newline = false;
                        }
                    },
                    .inl, .exp => {
                        try w.writeByte('\n');
                        newline = true;
                    },
                },
                else => if (e < f) try w.writeAll(", "),
            }
        }
    }
};

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Writer = std.io.Writer;
const ElementList = @This();
