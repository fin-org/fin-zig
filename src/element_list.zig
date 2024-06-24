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
};

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const ElementList = @This();
