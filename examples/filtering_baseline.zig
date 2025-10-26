//! Filtering and Baseline Example
//!
//! This example demonstrates:
//! - Filtering benchmarks by name pattern
//! - Saving benchmark results as a baseline
//! - Command-line argument parsing for filters
//!
//! Run with: zig build run-filtering_baseline
//! Or with filter: zig build run-filtering_baseline -- Fast
//! Or with baseline: zig build run-filtering_baseline -- "" baseline.json

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

fn slowOperation() void {
    var sum: u64 = 0;
    var i: u32 = 0;
    while (i < 10_000) : (i += 1) {
        sum += i;
    }
    global_sum = sum;
}

fn arrayOperation() void {
    var arr: [100]u64 = undefined;
    for (&arr, 0..) |*elem, i| {
        elem.* = i;
    }
    global_sum = arr[99];
}

fn stringOperation() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var list = std.ArrayList(u8){};
    defer list.deinit(allocator);

    var i: u32 = 0;
    while (i < 50) : (i += 1) {
        list.appendSlice(allocator, "test ") catch unreachable;
    }
    global_sum = list.items.len;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Parse command line arguments
    var args = std.process.args();
    _ = args.skip(); // Skip program name

    var suite = bench.BenchmarkSuite.init(allocator);
    defer suite.deinit();

    // Add all benchmarks
    try suite.add("Fast Operation", fastOperation);
    try suite.add("Slow Operation", slowOperation);
    try suite.add("Array Operation", arrayOperation);
    try suite.add("String Operation", stringOperation);

    // Check for filter argument
    if (args.next()) |filter_arg| {
        std.debug.print("Filtering benchmarks by: {s}\n", .{filter_arg});
        suite.setFilter(filter_arg);
    }

    // Check for baseline argument
    if (args.next()) |baseline_arg| {
        if (std.mem.eql(u8, baseline_arg, "--save-baseline")) {
            if (args.next()) |baseline_path| {
                suite.setBaseline(baseline_path);
            }
        }
    }

    try suite.run();
}
