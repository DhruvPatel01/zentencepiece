pub fn main() !void {
    var gpa_instance: std.heap.DebugAllocator(.{}) = .{};
    const gpa = gpa_instance.allocator();
    defer {
        const leaked = gpa_instance.deinit();
        std.debug.print("\n\n\nMemory leaks: {}\n", .{leaked});
    }
    // const gpa = std.heap.c_allocator;

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    if (args.len != 3) {
        std.debug.print("Usage: {s} model_path filepath_to_tokenize", .{args[0]});
        std.process.exit(22);
    }

    var tokenizer = try lib.Tokenizer.init(gpa, args[1]);
    defer tokenizer.deinit();

    const filename = args[2];
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    const reader = buf_reader.reader();
    var line = std.ArrayList(u8).init(gpa);
    defer line.deinit();
    const writer = line.writer();
    while (reader.streamUntilDelimiter(writer, '\n', null)) {
        const tokens = try tokenizer.tokenize(gpa, line.items);
        defer tokens.deinit();
        for (tokens.items) |token| {
            std.debug.print("{} ", .{token});
        }
        line.clearRetainingCapacity();
        std.debug.print("\n", .{});
    } else |err| switch (err) {
        error.EndOfStream => { // end of file
            if (line.items.len != 0) {
                const tokens = try tokenizer.tokenize(gpa, line.items);
                defer tokens.deinit();
                for (tokens.items) |token| {
                    std.debug.print("{} ", .{token});
                }
                line.clearRetainingCapacity();
                std.debug.print("\n", .{});
            }
        },
        else => return err, // Propagate error
    }
}

const std = @import("std");
const lib = @import("zentencepiece_lib");
