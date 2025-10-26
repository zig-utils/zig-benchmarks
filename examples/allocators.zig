const std = @import("std");
const bench = @import("bench");

var global_result: usize = 0;

// Benchmark function that uses the provided allocator
fn benchWithPageAllocator(allocator: std.mem.Allocator) void {
    var list = std.ArrayList(u64){};
    defer list.deinit(allocator);

    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        list.append(allocator, i) catch unreachable;
    }
    global_result = list.items.len;
}

fn benchWithGPA(allocator: std.mem.Allocator) void {
    var list = std.ArrayList(u64){};
    defer list.deinit(allocator);

    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        list.append(allocator, i) catch unreachable;
    }
    global_result = list.items.len;
}

fn benchWithArena(allocator: std.mem.Allocator) void {
    var list = std.ArrayList(u64){};
    defer list.deinit(allocator);

    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        list.append(allocator, i) catch unreachable;
    }
    global_result = list.items.len;
}

fn benchHashMapOperations(allocator: std.mem.Allocator) void {
    var map = std.AutoHashMap(u32, u32).init(allocator);
    defer map.deinit();

    var i: u32 = 0;
    while (i < 500) : (i += 1) {
        map.put(i, i * 2) catch unreachable;
    }

    var sum: u32 = 0;
    i = 0;
    while (i < 500) : (i += 1) {
        sum += map.get(i) orelse 0;
    }
    global_result = sum;
}

pub fn main() !void {
    // Create different allocators
    const page_allocator = std.heap.page_allocator;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const gpa_allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    // Suite with page allocator
    {
        var suite = bench.BenchmarkSuite.init(page_allocator);
        defer suite.deinit();

        try suite.addWithAllocator("ArrayList (PageAllocator)", benchWithPageAllocator);
        try suite.addWithAllocator("HashMap (PageAllocator)", benchHashMapOperations);

        const stdout = std.fs.File.stdout();
        var buf: [256]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "\n{s}[PageAllocator]{s}\n", .{ bench.Formatter.CYAN, bench.Formatter.RESET });
        try stdout.writeAll(msg);

        try suite.run();
    }

    // Suite with GPA
    {
        var suite = bench.BenchmarkSuite.init(gpa_allocator);
        defer suite.deinit();

        try suite.addWithAllocator("ArrayList (GPA)", benchWithGPA);
        try suite.addWithAllocator("HashMap (GPA)", benchHashMapOperations);

        const stdout = std.fs.File.stdout();
        var buf: [256]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "\n{s}[GeneralPurposeAllocator]{s}\n", .{ bench.Formatter.CYAN, bench.Formatter.RESET });
        try stdout.writeAll(msg);

        try suite.run();
    }

    // Suite with Arena
    {
        var suite = bench.BenchmarkSuite.init(arena_allocator);
        defer suite.deinit();

        try suite.addWithAllocator("ArrayList (Arena)", benchWithArena);
        try suite.addWithAllocator("HashMap (Arena)", benchHashMapOperations);

        const stdout = std.fs.File.stdout();
        var buf: [256]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "\n{s}[ArenaAllocator]{s}\n", .{ bench.Formatter.CYAN, bench.Formatter.RESET });
        try stdout.writeAll(msg);

        try suite.run();
    }
}
