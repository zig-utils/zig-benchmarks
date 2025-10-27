//! Comprehensive example demonstrating all Phase 2 advanced features:
//! - Benchmark groups and categories
//! - Automatic warmup detection
//! - Statistical outlier detection
//! - Parameterized benchmarks
//! - Multi-threaded benchmarks and scalability testing

const std = @import("std");
const bench = @import("bench");
const groups = @import("groups");
const warmup = @import("warmup");
const outliers = @import("outliers");
const parameterized = @import("parameterized");
const parallel = @import("parallel");

// Simple benchmark functions for demonstration
fn fastOperation() void {
    var sum: u64 = 0;
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        sum +%= i;
    }
    std.mem.doNotOptimizeAway(&sum);
}

fn mediumOperation() void {
    var sum: u64 = 0;
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        sum +%= i * i;
    }
    std.mem.doNotOptimizeAway(&sum);
}

fn slowOperation() void {
    var sum: u64 = 0;
    var i: u64 = 0;
    while (i < 10000) : (i += 1) {
        sum +%= i *% i *% i;
    }
    std.mem.doNotOptimizeAway(&sum);
}

// Parameterized function that takes a size parameter
fn arrayOperation(size: usize) void {
    var sum: u64 = 0;
    var i: usize = 0;
    while (i < size) : (i += 1) {
        sum +%= i;
    }
    std.mem.doNotOptimizeAway(&sum);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.fs.File.stdout();
    var buf: [512]u8 = undefined;

    const header = try std.fmt.bufPrint(&buf, "\n{s}=== Phase 2 Advanced Features Demo ==={s}\n\n", .{
        bench.Formatter.BOLD,
        bench.Formatter.RESET,
    });
    try stdout.writeAll(header);

    // 1. Benchmark Groups
    const section1 = try std.fmt.bufPrint(&buf, "{s}[1] Benchmark Groups & Categories{s}\n", .{
        bench.Formatter.CYAN,
        bench.Formatter.RESET,
    });
    try stdout.writeAll(section1);

    var manager = groups.GroupManager.init(allocator);
    defer manager.deinit();

    // Create algorithm comparison group
    const algo_group = try manager.addGroupWithDescription("Algorithms", "Algorithm performance comparison");
    try algo_group.suite.add("Fast Algorithm", fastOperation);
    try algo_group.suite.add("Medium Algorithm", mediumOperation);

    // Create data structure group
    const data_group = try manager.addGroupWithDescription("Data Structures", "Data structure operations");
    try data_group.suite.add("Array Operation", slowOperation);

    try manager.runAll();
    try stdout.writeAll("\n");

    // 2. Automatic Warmup Detection
    const section2 = try std.fmt.bufPrint(&buf, "{s}[2] Automatic Warmup Detection{s}\n", .{
        bench.Formatter.CYAN,
        bench.Formatter.RESET,
    });
    try stdout.writeAll(section2);

    const warmup_config = warmup.WarmupConfig{
        .max_warmup_iterations = 30,
        .min_warmup_iterations = 3,
        .stability_window = 5,
        .cv_threshold = 0.05,
    };

    const detector = warmup.WarmupDetector.init(warmup_config);

    const warmup_result = try detector.detect(mediumOperation, allocator);
    const warmup_line1 = try std.fmt.bufPrint(&buf, "  Detected optimal warmup: {d} iterations\n", .{warmup_result.optimal_iterations});
    try stdout.writeAll(warmup_line1);
    const warmup_line2 = try std.fmt.bufPrint(&buf, "  Coefficient of variation: {d:.4}\n", .{warmup_result.final_cv});
    try stdout.writeAll(warmup_line2);
    try stdout.writeAll("\n");

    // 3. Statistical Outlier Detection
    const section3 = try std.fmt.bufPrint(&buf, "{s}[3] Statistical Outlier Detection{s}\n", .{
        bench.Formatter.CYAN,
        bench.Formatter.RESET,
    });
    try stdout.writeAll(section3);

    // Create sample data with outliers
    const samples = [_]u64{ 100, 102, 98, 105, 101, 99, 500, 103, 97, 104, 1000 };
    const samples_f64: []const f64 = blk: {
        var samples_buf = try allocator.alloc(f64, samples.len);
        for (samples, 0..) |s, i| {
            samples_buf[i] = @floatFromInt(s);
        }
        break :blk samples_buf;
    };
    defer allocator.free(samples_f64);

    const detector_iqr = outliers.OutlierDetector.init(.{ .method = .iqr });

    const samples_u64 = try allocator.alloc(u64, samples.len);
    defer allocator.free(samples_u64);
    for (samples, 0..) |s, i| {
        samples_u64[i] = s;
    }

    var result_iqr = try detector_iqr.detectAndRemove(samples_u64, allocator);
    defer result_iqr.deinit();

    const outlier_line1 = try std.fmt.bufPrint(&buf, "  Original samples: {d}\n", .{samples.len});
    try stdout.writeAll(outlier_line1);
    const outlier_line2 = try std.fmt.bufPrint(&buf, "  After IQR outlier removal: {d}\n", .{result_iqr.cleaned_samples.len});
    try stdout.writeAll(outlier_line2);
    const outlier_line3 = try std.fmt.bufPrint(&buf, "  Removed: {d} outliers\n", .{result_iqr.outliers.len});
    try stdout.writeAll(outlier_line3);
    try stdout.writeAll("\n");

    // 4. Parameterized Benchmarks
    const section4 = try std.fmt.bufPrint(&buf, "{s}[4] Parameterized Benchmarks{s}\n", .{
        bench.Formatter.CYAN,
        bench.Formatter.RESET,
    });
    try stdout.writeAll(section4);

    const sizes = [_]usize{ 100, 1000, 10000 };
    const param_bench = parameterized.ParameterizedBenchmark(usize).init(
        allocator,
        "Array Size {d}",
        arrayOperation,
        &sizes,
    );

    var suite = try param_bench.generateSuite();
    defer suite.deinit();

    try suite.run();
    try stdout.writeAll("\n");

    // 5. Multi-threaded Benchmarks
    const section5 = try std.fmt.bufPrint(&buf, "{s}[5] Multi-threaded Benchmark{s}\n", .{
        bench.Formatter.CYAN,
        bench.Formatter.RESET,
    });
    try stdout.writeAll(section5);

    const parallel_config = parallel.ParallelConfig{
        .thread_count = 4,
        .iterations_per_thread = 1000,
        .warmup_iterations = 5,
    };

    const parallel_bench = parallel.ParallelBenchmark.init(
        allocator,
        "Parallel Fast Operation",
        fastOperation,
        parallel_config,
    );

    var parallel_result = try parallel_bench.run();
    defer parallel_result.deinit();

    try parallel.ParallelBenchmark.printResult(&parallel_result);
    try stdout.writeAll("\n");

    // 6. Scalability Testing
    const section6 = try std.fmt.bufPrint(&buf, "{s}[6] Scalability Test{s}\n", .{
        bench.Formatter.CYAN,
        bench.Formatter.RESET,
    });
    try stdout.writeAll(section6);

    const thread_counts = [_]usize{ 1, 2, 4, 8 };
    const scalability_test = parallel.ScalabilityTest.init(
        allocator,
        "Medium Operation Scalability",
        mediumOperation,
        &thread_counts,
        500,
    );

    try scalability_test.run();

    const footer = try std.fmt.bufPrint(&buf, "\n{s}=== Demo Complete ==={s}\n", .{
        bench.Formatter.BOLD,
        bench.Formatter.RESET,
    });
    try stdout.writeAll(footer);
}
