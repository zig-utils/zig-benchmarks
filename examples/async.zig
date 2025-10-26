//! Async Benchmark Example
//!
//! This example demonstrates:
//! - Benchmarking functions that can return errors
//! - Using AsyncBenchmarkSuite for error-handling functions
//! - Measuring allocation-heavy operations
//!
//! Run with: zig build run-async

const std = @import("std");
const bench = @import("bench");

// Global variable to prevent compiler optimization
var global_result: []u8 = undefined;

fn asyncFileOperation() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Simulate async file I/O operations
    const buffer = try allocator.alloc(u8, 1024);
    defer allocator.free(buffer);

    @memset(buffer, 'A');
    global_result = buffer;
}

fn asyncNetworkSimulation() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Simulate async network operations
    var data = std.ArrayList(u8){};
    defer data.deinit(allocator);

    var i: usize = 0;
    while (i < 256) : (i += 1) {
        try data.append(allocator, @intCast(i));
    }
    global_result = try data.toOwnedSlice(allocator);
    allocator.free(global_result);
}

fn asyncJsonParsing() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const json_str =
        \\{
        \\  "name": "benchmark",
        \\  "version": "1.0.0",
        \\  "items": [1, 2, 3, 4, 5]
        \\}
    ;

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    global_result = @constCast(json_str[0..10]);
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var suite = bench.AsyncBenchmarkSuite.init(allocator);
    defer suite.deinit();

    try suite.add("Async File Operations", asyncFileOperation);
    try suite.add("Async Network Simulation", asyncNetworkSimulation);
    try suite.add("Async JSON Parsing", asyncJsonParsing);

    try suite.run();
}
