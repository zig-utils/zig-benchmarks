const std = @import("std");
const bench = @import("bench");

// Import the advanced features
const export_mod = @import("export");
const comparison_mod = @import("comparison");
const memory_profiler = @import("memory_profiler");
const ci = @import("ci");

var global_sum: u64 = 0;

fn fastBenchmark() void {
    var sum: u64 = 0;
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        sum += i;
    }
    global_sum = sum;
}

fn mediumBenchmark() void {
    var sum: u64 = 0;
    var i: u32 = 0;
    while (i < 1_000) : (i += 1) {
        sum += i;
    }
    global_sum = sum;
}

fn slowBenchmark() void {
    var sum: u64 = 0;
    var i: u32 = 0;
    while (i < 10_000) : (i += 1) {
        sum += i;
    }
    global_sum = sum;
}

fn memoryIntensiveBenchmark(allocator: std.mem.Allocator) void {
    var list = std.ArrayList(u64){};
    defer list.deinit(allocator);

    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        list.append(allocator, i) catch unreachable;
    }
    global_sum = list.items.len;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Run benchmarks
    var suite = bench.BenchmarkSuite.init(allocator);
    defer suite.deinit();

    try suite.add("Fast Benchmark", fastBenchmark);
    try suite.add("Medium Benchmark", mediumBenchmark);
    try suite.add("Slow Benchmark", slowBenchmark);

    std.debug.print("\n{s}=== Running Benchmarks ==={s}\n", .{ bench.Formatter.BOLD, bench.Formatter.RESET });
    try suite.run();

    // Note: We can't easily access the results from suite.run(), so we'll run them again
    // In a real implementation, you'd modify BenchmarkSuite.run() to return results
    var results = std.ArrayList(bench.BenchmarkResult){};
    defer {
        for (results.items) |*result| {
            result.deinit();
        }
        results.deinit(allocator);
    }

    for (suite.benchmarks.items) |*benchmark| {
        const result = try benchmark.run(allocator);
        try results.append(allocator, result);
    }

    // 1. Export to JSON
    std.debug.print("\n{s}=== Exporting Results ==={s}\n", .{ bench.Formatter.BOLD, bench.Formatter.RESET });
    const exporter = export_mod.Exporter.init(allocator);
    try exporter.exportToFile(results.items, "benchmark_results.json", .json);
    std.debug.print("✓ Exported to JSON: benchmark_results.json\n", .{});

    // 2. Export to CSV
    try exporter.exportToFile(results.items, "benchmark_results.csv", .csv);
    std.debug.print("✓ Exported to CSV: benchmark_results.csv\n", .{});

    // 3. Compare with baseline (if exists)
    std.debug.print("\n{s}=== Baseline Comparison ==={s}\n", .{ bench.Formatter.BOLD, bench.Formatter.RESET });

    const baseline_exists = blk: {
        std.fs.cwd().access("baseline.json", .{}) catch break :blk false;
        break :blk true;
    };

    if (baseline_exists) {
        const comparator = comparison_mod.Comparator.init(allocator, 10.0);
        const comparisons = try comparator.compare(results.items, "baseline.json");
        defer allocator.free(comparisons);

        const stdout = std.fs.File.stdout();
        try comparator.printComparison(stdout, comparisons);
    } else {
        std.debug.print("No baseline found. Run with baseline.json to enable comparison.\n", .{});
        std.debug.print("Creating baseline from current results...\n", .{});
        try exporter.exportToFile(results.items, "baseline.json", .json);
        std.debug.print("✓ Baseline created: baseline.json\n", .{});
    }

    // 4. Memory Profiling Demo
    std.debug.print("\n{s}=== Memory Profiling Demo ==={s}\n", .{ bench.Formatter.BOLD, bench.Formatter.RESET });

    var profiling_allocator = memory_profiler.ProfilingAllocator.init(allocator);
    const tracked_allocator = profiling_allocator.allocator();

    // Run a memory-intensive benchmark
    var timer = try std.time.Timer.start();
    memoryIntensiveBenchmark(tracked_allocator);
    const elapsed = timer.read();

    const mem_result = memory_profiler.MemoryBenchmarkResult{
        .name = "Memory Intensive Benchmark",
        .time_ns = @floatFromInt(elapsed),
        .memory_stats = profiling_allocator.getStats(),
    };

    const stdout = std.fs.File.stdout();
    try mem_result.print(stdout);

    // 5. CI/CD Integration Demo
    std.debug.print("\n{s}=== CI/CD Integration Demo ==={s}\n", .{ bench.Formatter.BOLD, bench.Formatter.RESET });

    const ci_format = ci.detectCIEnvironment();
    std.debug.print("Detected CI environment: {s}\n", .{@tagName(ci_format)});

    var ci_helper = ci.CIHelper.init(allocator, .{
        .fail_on_regression = true,
        .regression_threshold = 10.0,
        .baseline_path = if (baseline_exists) "baseline.json" else null,
        .output_format = ci_format,
    });

    try ci_helper.generateSummary(results.items);

    if (baseline_exists) {
        const has_regression = try ci_helper.checkRegressions(results.items);
        if (has_regression and ci_helper.shouldFailBuild(has_regression)) {
            std.debug.print("\n{s}⚠️  Build would fail due to performance regressions{s}\n", .{ bench.Formatter.YELLOW, bench.Formatter.RESET });
            // In CI, you would: std.process.exit(1);
        }
    }

    std.debug.print("\n{s}✓ Advanced features demo complete!{s}\n", .{ bench.Formatter.GREEN, bench.Formatter.RESET });
}
