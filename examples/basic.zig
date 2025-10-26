//! Basic Benchmark Example
//!
//! This example demonstrates:
//! - Running multiple benchmarks in a suite
//! - Automatic comparison between benchmarks
//! - Benchmarking different complexity operations (Fibonacci, arrays, strings)
//!
//! Run with: zig build run-basic

const std = @import("std");
const bench = @import("bench");

// Global variable to prevent compiler optimization
var global_counter: u64 = 0;

fn fibonacci(n: u32) u64 {
    if (n <= 1) return n;
    return fibonacci(n - 1) + fibonacci(n - 2);
}

fn benchFib20() void {
    global_counter = fibonacci(20);
}

fn benchFib25() void {
    global_counter = fibonacci(25);
}

fn benchFib30() void {
    global_counter = fibonacci(30);
}

fn benchArrayAllocation() void {
    var arr: [1000]u64 = undefined;
    for (&arr, 0..) |*elem, i| {
        elem.* = i;
    }
    global_counter = arr[999];
}

fn benchHashMapOperations() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var map = std.AutoHashMap(u32, u32).init(allocator);
    defer map.deinit();

    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        map.put(i, i * 2) catch unreachable;
    }

    var sum: u32 = 0;
    i = 0;
    while (i < 100) : (i += 1) {
        sum += map.get(i) orelse 0;
    }
    global_counter = sum;
}

fn benchStringConcatenation() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var list = std.ArrayList(u8){};
    defer list.deinit(allocator);

    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        list.appendSlice(allocator, "Hello, World! ") catch unreachable;
    }
    global_counter = list.items.len;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var suite = bench.BenchmarkSuite.init(allocator);
    defer suite.deinit();

    try suite.add("Fibonacci(20)", benchFib20);
    try suite.add("Fibonacci(25)", benchFib25);
    try suite.add("Fibonacci(30)", benchFib30);
    try suite.add("Array Allocation [1000]", benchArrayAllocation);
    try suite.add("HashMap Operations [100]", benchHashMapOperations);
    try suite.add("String Concatenation [100]", benchStringConcatenation);

    try suite.run();
}
