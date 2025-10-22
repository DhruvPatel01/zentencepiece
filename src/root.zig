const std = @import("std");
const testing = std.testing;

const sentence_piece = @import("sentencepiece.pb.zig");
const daryheap = @import("indexed_dpq.zig");
pub const ModelProto = sentence_piece.ModelProto;

const Symbol = struct {
    start: u32,
    end: u32, //inclusive end
    frozen: bool = false,
    prev: u32,
    next: u32,
};

pub const Tokenizer = struct {
    state_machine: StateMachine,
    allocator: std.mem.Allocator,
    model: ModelProto,
    piece_id: std.StringHashMapUnmanaged(u32),
    id_score: []f32,

    pub fn init(allocator: std.mem.Allocator, model_path: []const u8) !Tokenizer {
        const model = try read_model(allocator, model_path);
        const state_machine = try StateMachine.new(allocator, &model);
        var piece_id = std.StringHashMapUnmanaged(u32){};
        var id_score = try allocator.alloc(f32, model.pieces.items.len);
        try piece_id.ensureTotalCapacity(allocator, @intCast(model.pieces.items.len));

        for (model.pieces.items, 0..) |*piece, i| {
            try piece_id.put(allocator, piece.piece.?, @intCast(i));
            id_score[i] = piece.score.?;
        }
        return Tokenizer{
            .state_machine = state_machine,
            .allocator = allocator,
            .model = model,
            .piece_id = piece_id,
            .id_score = id_score,
        };
    }

    pub fn deinit(self: *Tokenizer) void {
        self.state_machine.deinit(self.allocator);
        self.allocator.free(self.id_score);
        self.piece_id.deinit(self.allocator);
        self.model.deinit(self.allocator);
    }

    const HeapType = daryheap.IndexedDaryHeap(4);

    inline fn maybe_add(self: *Tokenizer, bytes: []const u8, heap: *HeapType, symbols: []Symbol, this_index: u32, next_index: u32) !void {
        if (symbols[this_index].frozen or symbols[next_index].frozen) return;
        const start = symbols[this_index].start;
        const end = symbols[next_index].end;

        const possible_id = self.piece_id.get(bytes[start .. end + 1]);
        if (possible_id == null) return;
        heap.changeScore(this_index, self.id_score[possible_id.?]);
    }

    pub noinline fn tokenize(self: *Tokenizer, allocator: std.mem.Allocator, bytes: []const u8) !std.ArrayList(u32) {
        if (bytes.len == 0)
            return std.ArrayList(u32).initCapacity(allocator, 0);
        var arena = std.heap.ArenaAllocator.init(allocator);
        const arena_allocator = arena.allocator();
        defer arena.deinit();

        // var tick = std.time.microTimestamp();
        const processed_bytes = try replace_spaces(arena_allocator, bytes);
        // std.debug.print("Replace spaces: {} us\n", .{std.time.microTimestamp() - tick});
        // tick = std.time.microTimestamp();

        const symbols = try self.state_machine.process(arena_allocator, processed_bytes);
        // std.debug.print("Processing: {} us\n", .{std.time.microTimestamp() - tick});

        var heap = try HeapType.initWithCapacity(arena_allocator, symbols.items.len);

        // tick = std.time.microTimestamp();
        for (1..symbols.items.len - 2) |i| {
            if (symbols.items[i].frozen or symbols.items[i + 1].frozen) continue;
            const start = symbols.items[i].start;
            const end = symbols.items[i + 1].end;
            if (self.piece_id.get(processed_bytes[start .. end + 1])) |id| {
                heap.add(i, self.id_score[id]);
            }
        }
        // std.debug.print("First pass: {} us\n", .{std.time.microTimestamp() - tick});

        var num_tokens = symbols.items.len - 2;

        // tick = std.time.microTimestamp();
        while (heap.size > 0) {
            const this_index: u32 = @intCast(heap.peekTop());
            const this_symbol = &symbols.items[this_index];
            const next_symbol = &symbols.items[this_symbol.next];

            if (heap.keyExists(this_symbol.next)) {
                heap.removeKey(this_symbol.next);
            }

            this_symbol.end = next_symbol.end;
            next_symbol.end = 0;
            next_symbol.start = 0;
            this_symbol.next = next_symbol.next;
            symbols.items[this_symbol.next].prev = this_index;
            num_tokens -= 1;

            if (symbols.items[this_symbol.next].frozen) {
                heap.removeKey(this_index);
            } else {
                const start = this_symbol.start;
                const end = symbols.items[this_symbol.next].end;
                if (self.piece_id.get(processed_bytes[start .. end + 1])) |id| {
                    heap.changeScore(this_index, self.id_score[id]);
                } else {
                    heap.removeKey(this_index);
                }
            }

            if (!symbols.items[this_symbol.prev].frozen) {
                const start = symbols.items[this_symbol.prev].start;
                const end = this_symbol.end;
                if (self.piece_id.get(processed_bytes[start .. end + 1])) |id| {
                    heap.addOrChange(this_symbol.prev, self.id_score[id]);
                } else if (heap.keyExists(this_symbol.prev)) {
                    heap.removeKey(this_symbol.prev);
                }
            }
        }
        // std.debug.print("Remaning pass: {} us\n", .{std.time.microTimestamp() - tick});

        var tokens = try std.ArrayList(u32).initCapacity(allocator, num_tokens);
        var i: usize = 1;
        var unknown_buffer = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 };
        while (i != symbols.items.len - 1) {
            const start = symbols.items[i].start;
            const end = symbols.items[i].end;
            i = symbols.items[i].next;
            if (self.piece_id.get(processed_bytes[start .. end + 1])) |v| {
                try tokens.append(allocator, v);
            } else {
                for (processed_bytes[start .. end + 1]) |byte| {
                    const id = try std.fmt.bufPrint(&unknown_buffer, "<0x{X:02}>", .{byte});
                    // std.debug.print("{s}", .{id});
                    try tokens.append(allocator, self.piece_id.get(id).?);
                }
            }
        }

        return tokens;
    }
};

pub const StateMachine = struct {
    transition_table: std.ArrayListUnmanaged([256]u32),
    valid_states: std.ArrayListUnmanaged(bool),

    pub fn new(allocator: std.mem.Allocator, model: *const ModelProto) !StateMachine {
        var transition_table = try std.ArrayListUnmanaged([256]u32).initCapacity(allocator, 512);
        var valid_states = try std.ArrayListUnmanaged(bool).initCapacity(allocator, 512);

        try transition_table.append(allocator, [_]u32{0} ** 256);
        for (model.pieces.items) |*piece| {
            if (piece.type.? != sentence_piece.ModelProto.SentencePiece.Type.USER_DEFINED) {
                continue;
            }
            var state: u32 = 0;
            for (piece.piece.?) |char| {
                if (transition_table.items[state][char] == 0) {
                    const new_state: u32 = @intCast(valid_states.items.len);
                    try transition_table.append(allocator, [_]u32{0} ** 256);
                    try valid_states.append(allocator, false);
                    transition_table.items[state][char] = new_state;
                }
                state = transition_table.items[state][char];
            }
            valid_states.items[state] = true;
        }
        return .{ .transition_table = transition_table, .valid_states = valid_states };
    }

    pub fn deinit(self: *StateMachine, allocator: std.mem.Allocator) void {
        self.transition_table.deinit(allocator);
        self.valid_states.deinit(allocator);
    }

    pub fn process(self: *const StateMachine, allocator: std.mem.Allocator, string: []const u8) !std.ArrayListUnmanaged(Symbol) {
        var state: u32 = 0;
        var symbols = try std.ArrayListUnmanaged(Symbol).initCapacity(allocator, 16);
        var start: u32 = 0;
        var end: u32 = 0;
        var i: u32 = 0;
        var frozen = false;

        symbols.appendAssumeCapacity(.{ .start = 0, .end = 0, .prev = 0, .next = 1, .frozen = true });

        while (true) {
            if (i == string.len or self.transition_table.items[state][string[i]] == 0) {
                // try to move end to the end of unicode code point
                if (start == end) {
                    const code_size: u32 = code_point_lengths[(string[start] >> 4) & 0xF];
                    end = @min(string.len - 1, start + code_size - 1);
                }
                try symbols.append(allocator, Symbol{
                    .start = start,
                    .end = end,
                    .frozen = frozen,
                    .prev = @intCast(symbols.items.len - 1),
                    .next = @intCast(symbols.items.len + 1),
                });
                start = end + 1;
                if (start >= string.len) break;
                end = start;
                i = start;
                state = 0;
                frozen = false;
            } else {
                state = self.transition_table.items[state][string[i]];
                if (self.valid_states.items[state]) {
                    end = i;
                    frozen = true;
                }
                i += 1;
            }
        }
        try symbols.append(allocator, .{ .start = 0, .end = 0, .prev = @intCast(symbols.items.len - 1), .next = 0, .frozen = true });
        return symbols;
    }
};

pub fn replace_spaces(arena: std.mem.Allocator, string: []const u8) ![]u8 {
    // allocating conservatively, as at some point buffer is going to overflow and we will double the buffer anyways
    var new_string = try std.ArrayListUnmanaged(u8).initCapacity(arena, string.len * 2);
    var i: usize = 0;
    while (i < string.len) {
        if (string[i] == ' ') {
            try new_string.appendSlice(arena, "▁");
            i += 1;
        } else {
            @branchHint(.likely);
            const code_length = code_point_lengths[(string[i] >> 4) & 0xF];
            try new_string.appendSlice(arena, string[i .. i + code_length]);
            i += code_length;
        }
    }
    return new_string.toOwnedSlice(arena);
}

const code_point_lengths = [_]u8{ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 3, 4 };

// Code to read the protobuf model
fn read_model(allocator: std.mem.Allocator, path: []const u8) !ModelProto {
    var model_file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    defer model_file.close();
    var buffer: [2048]u8 = undefined;
    var reader = model_file.reader(&buffer);
    return ModelProto.decode(&reader.interface, allocator);
}
