const std = @import("std");
const bench = @import("bench");

var global_sum: u64 = 0;

fn fastOperation() void {
    var sum: u64 = 0;
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        sum += i;
    }
    global_sum = sum;
}

fn mediumOperation() void {
    var sum: u64 = 0;
    var i: u32 = 0;
    while (i < 10_000) : (i += 1) {
        sum += i;
    }
    global_sum = sum;
}

fn slowOperation() void {
    var sum: u64 = 0;
    var i: u32 = 0;
    while (i < 1_000_000) : (i += 1) {
        sum += i;
    }
    global_sum = sum;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var suite = bench.BenchmarkSuite.init(allocator);
    defer suite.deinit();

    // Fast operation - use more iterations
    try suite.addWithOptions("Fast Loop (100 iterations)", fastOperation, .{
        .warmup_iterations = 10,
        .min_iterations = 100,
        .max_iterations = 100_000,
        .min_time_ns = 500_000_000, // 0.5 seconds
    });

    // Medium operation - use default settings
    try suite.add("Medium Loop (10k iterations)", mediumOperation);

    // Slow operation - use fewer iterations
    try suite.addWithOptions("Slow Loop (1M iterations)", slowOperation, .{
        .warmup_iterations = 2,
        .min_iterations = 5,
        .max_iterations = 100,
        .min_time_ns = 2_000_000_000, // 2 seconds
    });

    try suite.run();
}
