pub fn main(init: std.process.Init) !void {
    var gpa_instance: std.heap.DebugAllocator(.{}) = .{};
    const gpa = gpa_instance.allocator();
    const arena = init.arena.allocator();

    defer {
        const leaked = gpa_instance.deinit();
        std.debug.print("\n\n\nMemory leaks: {}\n", .{leaked});
    }
    // const gpa = std.heap.c_allocator;

    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 3) {
        std.debug.print("Usage: {s} model_path filepath_to_tokenize", .{args[0]});
        std.process.exit(22);
    }

    var tokenizer = try lib.Tokenizer.init(init.io, gpa, args[1]);
    defer tokenizer.deinit();

    const filename = args[2];
    const file = try std.Io.Dir.cwd().openFile(init.io, filename, .{});
    defer file.close(init.io);

    var buffer: [2 * 1024]u8 = undefined;
    var reader = file.reader(init.io, &buffer);
    var allocating_writer = std.Io.Writer.Allocating.init(gpa);
    defer allocating_writer.deinit();

    while (reader.interface.streamDelimiter(&allocating_writer.writer, '\n')) |_| {
        const line = allocating_writer.written();
        var tokens = try tokenizer.tokenize(gpa, line);
        defer tokens.deinit(gpa);
        for (tokens.items) |token| {
            std.debug.print("{} ", .{token});
        }
        allocating_writer.clearRetainingCapacity();
        reader.interface.toss(1);
        std.debug.print("\n", .{});
    } else |err| switch (err) {
        error.EndOfStream => { // end of file
            const line = allocating_writer.written();
            var tokens = try tokenizer.tokenize(gpa, line);
            defer tokens.deinit(gpa);
            for (tokens.items) |token| {
                std.debug.print("{} ", .{token});
            }
            allocating_writer.clearRetainingCapacity();
            std.debug.print("\n", .{});
        },
        else => return err, // Propagate error
    }
}

const std = @import("std");
const lib = @import("zentencepiece_lib");
