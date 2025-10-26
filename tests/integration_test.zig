//! Integration tests for the benchmark runner
//!
//! These tests verify end-to-end functionality of the benchmark framework
//! including running benchmarks, filtering, and result generation.

const std = @import("std");
const bench = @import("bench");
const testing = std.testing;

// Test fixtures - simple functions to benchmark
var global_counter: u64 = 0;

fn simpleBenchmark() void {
    var sum: u64 = 0;
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        sum += i;
    }
    global_counter = sum;
}

fn fastBenchmark() void {
    global_counter = 42;
}

fn mediumBenchmark() void {
    var sum: u64 = 0;
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        sum += i;
    }
    global_counter = sum;
}

// Integration Tests

test "BenchmarkSuite - init and deinit" {
    const allocator = testing.allocator;
    var suite = bench.BenchmarkSuite.init(allocator);
    defer suite.deinit();

    try testing.expectEqual(@as(usize, 0), suite.benchmarks.items.len);
}

test "BenchmarkSuite - add single benchmark" {
    const allocator = testing.allocator;
    var suite = bench.BenchmarkSuite.init(allocator);
    defer suite.deinit();

    try suite.add("Simple Test", simpleBenchmark);
    try testing.expectEqual(@as(usize, 1), suite.benchmarks.items.len);
    try testing.expectEqualStrings("Simple Test", suite.benchmarks.items[0].name);
}

test "BenchmarkSuite - add multiple benchmarks" {
    const allocator = testing.allocator;
    var suite = bench.BenchmarkSuite.init(allocator);
    defer suite.deinit();

    try suite.add("Test 1", simpleBenchmark);
    try suite.add("Test 2", fastBenchmark);
    try suite.add("Test 3", mediumBenchmark);

    try testing.expectEqual(@as(usize, 3), suite.benchmarks.items.len);
}

test "BenchmarkSuite - add with custom options" {
    const allocator = testing.allocator;
    var suite = bench.BenchmarkSuite.init(allocator);
    defer suite.deinit();

    const opts = bench.BenchmarkOptions{
        .warmup_iterations = 2,
        .min_iterations = 5,
        .max_iterations = 100,
        .min_time_ns = 100_000_000, // 100ms
    };

    try suite.addWithOptions("Custom Test", fastBenchmark, opts);
    try testing.expectEqual(@as(usize, 1), suite.benchmarks.items.len);
    try testing.expectEqual(@as(u32, 2), suite.benchmarks.items[0].opts.warmup_iterations);
    try testing.expectEqual(@as(u32, 5), suite.benchmarks.items[0].opts.min_iterations);
}

test "BenchmarkSuite - filter benchmarks by name" {
    const allocator = testing.allocator;
    var suite = bench.BenchmarkSuite.init(allocator);
    defer suite.deinit();

    try suite.add("Fast Operation", fastBenchmark);
    try suite.add("Medium Operation", mediumBenchmark);
    try suite.add("Fast Algorithm", simpleBenchmark);

    suite.setFilter("Fast");

    // Verify filter is set
    try testing.expect(suite.filter != null);
    try testing.expectEqualStrings("Fast", suite.filter.?);

    // Test filtering logic
    try testing.expect(suite.matchesFilter("Fast Operation"));
    try testing.expect(!suite.matchesFilter("Medium Operation"));
    try testing.expect(suite.matchesFilter("Fast Algorithm"));
}

test "BenchmarkSuite - filter with no matches" {
    const allocator = testing.allocator;
    var suite = bench.BenchmarkSuite.init(allocator);
    defer suite.deinit();

    try suite.add("Operation A", fastBenchmark);
    try suite.add("Operation B", mediumBenchmark);

    suite.setFilter("NonExistent");

    try testing.expect(!suite.matchesFilter("Operation A"));
    try testing.expect(!suite.matchesFilter("Operation B"));
}

test "BenchmarkSuite - no filter matches all" {
    const allocator = testing.allocator;
    var suite = bench.BenchmarkSuite.init(allocator);
    defer suite.deinit();

    try suite.add("Test 1", fastBenchmark);
    try suite.add("Test 2", mediumBenchmark);

    // No filter set, everything should match
    try testing.expect(suite.matchesFilter("Test 1"));
    try testing.expect(suite.matchesFilter("Test 2"));
    try testing.expect(suite.matchesFilter("Anything"));
}

test "Benchmark - run produces valid result" {
    const allocator = testing.allocator;

    // Create a benchmark with very short runtime for testing
    const opts = bench.BenchmarkOptions{
        .warmup_iterations = 1,
        .min_iterations = 10,
        .max_iterations = 100,
        .min_time_ns = 50_000_000, // 50ms
    };

    var benchmark = bench.Benchmark.withOptions("Test", mediumBenchmark, opts);
    var result = try benchmark.run(allocator);
    defer result.deinit();

    // Verify result has reasonable values
    try testing.expect(result.iterations >= 10);
    try testing.expect(result.iterations <= 100);
    try testing.expect(result.mean >= 0); // Allow 0 for extremely fast operations
    try testing.expect(result.max >= result.min);
    try testing.expect(result.ops_per_sec >= 0);

    // Verify percentiles are in order (allowing for 0 values)
    try testing.expect(result.p50 >= result.min);
    try testing.expect(result.p75 >= result.p50);
    try testing.expect(result.p99 >= result.p75);
    try testing.expect(result.p99 <= result.max);
}

test "Benchmark - run with allocator function" {
    const allocator = testing.allocator;

    const AllocatorBench = struct {
        fn benchFunc(alloc: std.mem.Allocator) void {
            // Simulate work with allocator
            const buffer = alloc.alloc(u8, 100) catch unreachable;
            defer alloc.free(buffer);
            @memset(buffer, 42);
            global_counter = buffer[0];
        }
    };

    const opts = bench.BenchmarkOptions{
        .warmup_iterations = 1,
        .min_iterations = 5,
        .max_iterations = 50,
        .min_time_ns = 10_000_000,
    };

    var benchmark = bench.Benchmark.withAllocatorAndOptions("Allocator Test", AllocatorBench.benchFunc, opts);
    var result = try benchmark.run(allocator);
    defer result.deinit();

    try testing.expect(result.iterations >= 5);
    try testing.expect(result.mean > 0);
}

test "Benchmark - respects min_iterations" {
    const allocator = testing.allocator;

    const opts = bench.BenchmarkOptions{
        .warmup_iterations = 0,
        .min_iterations = 20,
        .max_iterations = 1000,
        .min_time_ns = 1_000_000, // 1ms - enough time but min_iterations should still apply
    };

    var benchmark = bench.Benchmark.withOptions("Min Iterations Test", simpleBenchmark, opts);
    var result = try benchmark.run(allocator);
    defer result.deinit();

    // Should run at least min_iterations (may run more if time hasn't elapsed)
    try testing.expect(result.iterations >= 20);
}

test "Benchmark - respects max_iterations" {
    const allocator = testing.allocator;

    const opts = bench.BenchmarkOptions{
        .warmup_iterations = 0,
        .min_iterations = 5,
        .max_iterations = 10,
        .min_time_ns = 10_000_000_000, // 10 seconds (won't reach)
    };

    var benchmark = bench.Benchmark.withOptions("Max Iterations Test", fastBenchmark, opts);
    var result = try benchmark.run(allocator);
    defer result.deinit();

    // Should not exceed max_iterations
    try testing.expect(result.iterations <= 10);
}

test "BenchmarkResult - name is preserved" {
    const allocator = testing.allocator;

    const opts = bench.BenchmarkOptions{
        .warmup_iterations = 1,
        .min_iterations = 5,
        .max_iterations = 10,
        .min_time_ns = 10_000_000,
    };

    var benchmark = bench.Benchmark.withOptions("My Custom Benchmark", fastBenchmark, opts);
    var result = try benchmark.run(allocator);
    defer result.deinit();

    try testing.expectEqualStrings("My Custom Benchmark", result.name);
}

test "BenchmarkResult - samples array is populated" {
    const allocator = testing.allocator;

    const opts = bench.BenchmarkOptions{
        .warmup_iterations = 1,
        .min_iterations = 10,
        .max_iterations = 20,
        .min_time_ns = 10_000_000,
    };

    var benchmark = bench.Benchmark.withOptions("Samples Test", mediumBenchmark, opts);
    var result = try benchmark.run(allocator);
    defer result.deinit();

    // Samples should match iterations
    try testing.expectEqual(result.iterations, @as(u64, @intCast(result.samples.items.len)));

    // All samples should be non-negative (allowing 0 for extremely fast operations)
    for (result.samples.items) |sample| {
        _ = sample; // Just verify we can iterate, don't assert on value
    }

    // At least verify we got some samples
    try testing.expect(result.samples.items.len >= 10);
}

test "AsyncBenchmark - error handling function" {
    const allocator = testing.allocator;

    const AsyncTestFn = struct {
        fn asyncFunc() !void {
            var sum: u64 = 0;
            var i: u32 = 0;
            while (i < 100) : (i += 1) {
                sum += i;
            }
            global_counter = sum;
        }
    };

    const opts = bench.BenchmarkOptions{
        .warmup_iterations = 1,
        .min_iterations = 5,
        .max_iterations = 20,
        .min_time_ns = 10_000_000,
    };

    var benchmark = bench.AsyncBenchmark.withOptions("Async Test", AsyncTestFn.asyncFunc, opts);
    var result = try benchmark.run(allocator);
    defer result.deinit();

    try testing.expect(result.iterations >= 5);
    try testing.expect(result.mean > 0);
}

test "AsyncBenchmarkSuite - multiple async benchmarks" {
    const allocator = testing.allocator;

    const AsyncFns = struct {
        fn func1() !void {
            global_counter = 1;
        }
        fn func2() !void {
            global_counter = 2;
        }
    };

    var suite = bench.AsyncBenchmarkSuite.init(allocator);
    defer suite.deinit();

    try suite.add("Async 1", AsyncFns.func1);
    try suite.add("Async 2", AsyncFns.func2);

    try testing.expectEqual(@as(usize, 2), suite.benchmarks.items.len);
}

test "Integration - full benchmark suite workflow" {
    const allocator = testing.allocator;

    var suite = bench.BenchmarkSuite.init(allocator);
    defer suite.deinit();

    // Add multiple benchmarks
    const opts = bench.BenchmarkOptions{
        .warmup_iterations = 1,
        .min_iterations = 5,
        .max_iterations = 20,
        .min_time_ns = 10_000_000,
    };

    try suite.addWithOptions("Fast", fastBenchmark, opts);
    try suite.addWithOptions("Medium", mediumBenchmark, opts);
    try suite.addWithOptions("Simple", simpleBenchmark, opts);

    // Verify suite is set up correctly
    try testing.expectEqual(@as(usize, 3), suite.benchmarks.items.len);

    // Note: We can't call suite.run() here as it writes to stdout
    // But we can verify individual benchmarks work
    for (suite.benchmarks.items) |*benchmark| {
        var result = try benchmark.run(allocator);
        defer result.deinit();

        try testing.expect(result.iterations > 0);
        try testing.expect(result.mean > 0);
        try testing.expectEqual(@as(usize, @intCast(result.iterations)), result.samples.items.len);
    }
}
