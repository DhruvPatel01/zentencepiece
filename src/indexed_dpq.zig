/// this heap implementation doesn't reallocate memory dynamically
pub fn IndexedDaryHeap(comptime d: comptime_int) type {
    if (d < 2) @compileError("d >= 2 for IndexedDaryHeap");

    return struct {
        key_to_position: []usize,
        position_to_key: []usize,
        scores: []f32,
        size: usize = 0,
        arena: std.heap.ArenaAllocator,

        const Self = @This();

        pub fn initWithCapacity(gpa: std.mem.Allocator, capacity: usize) !Self {
            var arena = std.heap.ArenaAllocator.init(gpa);
            const allocator = arena.allocator();
            const dpq = Self{
                .key_to_position = try allocator.alloc(usize, capacity),
                .position_to_key = try allocator.alloc(usize, capacity),
                .scores = try allocator.alloc(f32, capacity),
                .size = 0,
                .arena = arena,
            };
            for (0..capacity) |i| {
                dpq.key_to_position[i] = std.math.maxInt(usize);
                dpq.position_to_key[i] = std.math.maxInt(usize);
                dpq.scores[i] = std.math.floatMin(f32);
            }
            return dpq;
        }

        pub fn deinit(self: *Self) void {
            self.arena.deinit();
            self.size = 0;
        }

        pub inline fn peekTop(self: *Self) usize {
            return self.position_to_key[0];
        }

        pub inline fn peekFirstScore(self: *Self) usize {
            return self.scores[0];
        }

        pub inline fn keyExists(self: *Self, key: usize) bool {
            return self.key_to_position[key] < self.size;
        }

        pub inline fn positionOf(self: *Self, key: usize) usize {
            return self.key_to_position[key];
        }

        pub fn addOrChange(self: *Self, key: usize, score: f32) void {
            if (self.keyExists(key)) {
                self.changeScore(key, score);
            } else {
                self.add(key, score);
            }
        }

        pub fn add(self: *Self, key: usize, score: f32) void {
            self.key_to_position[key] = self.size;
            self.scores[self.size] = score;
            self.position_to_key[self.size] = key;
            self.size += 1;
            self.shiftUp(self.size - 1);
        }

        pub fn changeScore(self: *Self, key: usize, new_score: f32) void {
            const position = self.key_to_position[key];
            const score = self.scores[position];
            self.scores[position] = new_score;
            if (position > 0 and new_score > score) {
                self.shiftUp(position);
            } else if (position < self.size and new_score < score) {
                self.shiftDown(position);
            }
        }

        pub fn shiftUp(pq: *Self, position: usize) void {
            const key = pq.position_to_key[position];
            const score = pq.scores[position];

            var current_position = position;
            while (current_position > 0) {
                const parent_position = parentOf(current_position);
                if (pq.scores[parent_position] >= score) break;
                const parent_key = pq.position_to_key[parent_position];
                pq.key_to_position[parent_key] = current_position;
                pq.position_to_key[current_position] = parent_key;
                pq.scores[current_position] = pq.scores[parent_position];

                current_position = parent_position;
            }
            pq.key_to_position[key] = current_position;
            pq.position_to_key[current_position] = key;
            pq.scores[current_position] = score;
        }

        pub fn shiftDown(pq: *Self, position: usize) void {
            const key = pq.position_to_key[position];
            const score = pq.scores[position];

            var current_position = position;
            while (true) {
                const first_child = firstChild(current_position);
                if (first_child >= pq.size) break;
                var biggest_child = pq.scores[first_child];
                var biggest_child_idx = first_child;
                for (first_child + 1..@min(first_child + d, pq.size)) |i| {
                    if (pq.scores[i] > biggest_child) {
                        biggest_child_idx = i;
                        biggest_child = pq.scores[i];
                    }
                }
                if (biggest_child <= score) break;
                const child_key = pq.position_to_key[biggest_child_idx];
                pq.position_to_key[current_position] = child_key;
                pq.key_to_position[child_key] = current_position;
                pq.scores[current_position] = biggest_child;
                current_position = biggest_child_idx;
            }

            pq.key_to_position[key] = current_position;
            pq.position_to_key[current_position] = key;
            pq.scores[current_position] = score;
        }

        pub fn removePosition(self: *Self, position: usize) void {
            const key_to_delete = self.position_to_key[position];
            self.key_to_position[key_to_delete] = std.math.maxInt(usize);

            const key_at_end = self.position_to_key[self.size - 1];
            self.scores[position] = self.scores[self.size - 1];
            self.position_to_key[position] = key_at_end;
            self.key_to_position[key_at_end] = position;
            self.size -= 1;

            self.shiftDown(position);
        }

        pub fn removeKey(self: *Self, key: usize) void {
            const position = self.key_to_position[key];
            self.removePosition(position);
        }

        inline fn parentOf(idx: usize) usize {
            return (idx - 1) / d;
        }

        inline fn firstChild(idx: usize) usize {
            return idx * d + 1;
        }

        pub fn checkInvariant(self: *Self) !void {
            for (0..self.size) |i| {
                for (0..d) |j| {
                    const child = firstChild(i) + j;
                    if (child >= self.size) break;
                    try std.testing.expect(self.scores[i] >= self.scores[child]);
                }
            }
        }
    };
}

test "heap works" {
    // pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const IndexedTernaryHeap = IndexedDaryHeap(2);
    var dpq = try IndexedTernaryHeap.initWithCapacity(allocator, 10);
    defer dpq.deinit();

    try dpq.add(0, 0.0);
    try dpq.add(1, 1.0);
    try dpq.add(2, 2.0);
    try dpq.add(3, 3.0);
    try dpq.add(4, 4.0);
    try dpq.add(5, 5.0);

    try dpq.checkInvariant();

    dpq.changeScore(5, 50.0);
    try dpq.checkInvariant();
    try std.testing.expect(dpq.peekTop() == 5);

    dpq.changeScore(5, 0.5);
    try dpq.checkInvariant();
    try std.testing.expectEqual(4, dpq.peekTop());

    dpq.changeScore(4, 40.0);
    try dpq.checkInvariant();
    try std.testing.expectEqual(4, dpq.peekTop());

    try dpq.removePosition(0);
    try dpq.checkInvariant();
    try std.testing.expectEqual(3, dpq.peekTop());
    std.debug.print("{any}\n{any}\n\n", .{ dpq.scores, dpq.position_to_key });
}

const std = @import("std");
