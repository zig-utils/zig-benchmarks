//! Parallel/Multi-threaded Benchmark Support
//!
//! Features:
//! - Run benchmarks across multiple threads
//! - Test thread scalability
//! - Measure parallel performance characteristics
//! - Thread-safe result aggregation

const std = @import("std");
const bench = @import("bench");
const Allocator = std.mem.Allocator;
const Thread = std.Thread;

/// Configuration for parallel benchmarks
pub const ParallelConfig = struct {
    /// Number of threads to use
    thread_count: usize = 4,

    /// Iterations per thread
    iterations_per_thread: u32 = 1000,

    /// Warmup iterations per thread
    warmup_iterations: u32 = 5,
};

/// Result from a parallel benchmark
pub const ParallelResult = struct {
    name: []const u8,
    thread_count: usize,
    total_iterations: u64,
    total_time_ns: u64,
    mean_per_thread_ns: f64,
    ops_per_sec_total: f64,
    ops_per_sec_per_thread: f64,
    thread_results: []ThreadResult,
    allocator: Allocator,

    pub fn deinit(self: *ParallelResult) void {
        self.allocator.free(self.thread_results);
    }
};

/// Result from a single thread
pub const ThreadResult = struct {
    thread_id: usize,
    iterations: u64,
    total_time_ns: u64,
    mean_ns: f64,
};

/// Context for thread execution
const ThreadContext = struct {
    func: *const fn () void,
    iterations: u32,
    warmup: u32,
    result: ThreadResult,
};

/// Parallel benchmark runner
pub const ParallelBenchmark = struct {
    name: []const u8,
    func: *const fn () void,
    config: ParallelConfig,
    allocator: Allocator,

    pub fn init(allocator: Allocator, name: []const u8, func: *const fn () void, config: ParallelConfig) ParallelBenchmark {
        return .{
            .name = name,
            .func = func,
            .config = config,
            .allocator = allocator,
        };
    }

    /// Run the benchmark in parallel
    pub fn run(self: *const ParallelBenchmark) !ParallelResult {
        var threads = try self.allocator.alloc(Thread, self.config.thread_count);
        defer self.allocator.free(threads);

        var contexts = try self.allocator.alloc(ThreadContext, self.config.thread_count);
        defer self.allocator.free(contexts);

        // Initialize contexts
        for (contexts, 0..) |*ctx, i| {
            ctx.* = .{
                .func = self.func,
                .iterations = self.config.iterations_per_thread,
                .warmup = self.config.warmup_iterations,
                .result = .{
                    .thread_id = i,
                    .iterations = 0,
                    .total_time_ns = 0,
                    .mean_ns = 0,
                },
            };
        }

        // Spawn threads
        for (threads, 0..) |*thread, i| {
            thread.* = try Thread.spawn(.{}, runThread, .{&contexts[i]});
        }

        // Wait for all threads
        for (threads) |thread| {
            thread.join();
        }

        // Aggregate results
        var thread_results = try self.allocator.alloc(ThreadResult, self.config.thread_count);
        var total_iterations: u64 = 0;
        var total_time: u64 = 0;
        var sum_mean: f64 = 0;

        for (contexts, 0..) |ctx, i| {
            thread_results[i] = ctx.result;
            total_iterations += ctx.result.iterations;
            total_time += ctx.result.total_time_ns;
            sum_mean += ctx.result.mean_ns;
        }

        const mean_per_thread = sum_mean / @as(f64, @floatFromInt(self.config.thread_count));
        const ops_per_sec_total = (@as(f64, @floatFromInt(total_iterations)) / @as(f64, @floatFromInt(total_time))) * 1_000_000_000.0;
        const ops_per_sec_per_thread = ops_per_sec_total / @as(f64, @floatFromInt(self.config.thread_count));

        return ParallelResult{
            .name = self.name,
            .thread_count = self.config.thread_count,
            .total_iterations = total_iterations,
            .total_time_ns = total_time,
            .mean_per_thread_ns = mean_per_thread,
            .ops_per_sec_total = ops_per_sec_total,
            .ops_per_sec_per_thread = ops_per_sec_per_thread,
            .thread_results = thread_results,
            .allocator = self.allocator,
        };
    }

    /// Print parallel benchmark results
    pub fn printResult(result: *const ParallelResult) !void {
        const stdout = std.fs.File.stdout();
        var buf: [512]u8 = undefined;

        const header = try std.fmt.bufPrint(&buf, "\n{s}=== Parallel Benchmark: {s} ==={s}\n", .{
            bench.Formatter.BOLD,
            result.name,
            bench.Formatter.RESET,
        });
        try stdout.writeAll(header);

        const threads_line = try std.fmt.bufPrint(&buf, "  {s}Threads:{s} {d}\n", .{
            bench.Formatter.DIM,
            bench.Formatter.RESET,
            result.thread_count,
        });
        try stdout.writeAll(threads_line);

        const iters_line = try std.fmt.bufPrint(&buf, "  {s}Total Iterations:{s} {d}\n", .{
            bench.Formatter.DIM,
            bench.Formatter.RESET,
            result.total_iterations,
        });
        try stdout.writeAll(iters_line);

        const mean_line = try std.fmt.bufPrint(&buf, "  {s}Mean/Thread:{s} {s}{d:.2} µs{s}\n", .{
            bench.Formatter.DIM,
            bench.Formatter.RESET,
            bench.Formatter.GREEN,
            result.mean_per_thread_ns / 1000.0,
            bench.Formatter.RESET,
        });
        try stdout.writeAll(mean_line);

        const ops_total_line = try std.fmt.bufPrint(&buf, "  {s}Total Ops/sec:{s} {s}{d:.2}{s}\n", .{
            bench.Formatter.DIM,
            bench.Formatter.RESET,
            bench.Formatter.MAGENTA,
            result.ops_per_sec_total,
            bench.Formatter.RESET,
        });
        try stdout.writeAll(ops_total_line);

        const ops_thread_line = try std.fmt.bufPrint(&buf, "  {s}Ops/sec/Thread:{s} {s}{d:.2}{s}\n", .{
            bench.Formatter.DIM,
            bench.Formatter.RESET,
            bench.Formatter.MAGENTA,
            result.ops_per_sec_per_thread,
            bench.Formatter.RESET,
        });
        try stdout.writeAll(ops_thread_line);
    }
};

/// Thread function that runs the benchmark
fn runThread(ctx: *ThreadContext) void {
    var timer = std.time.Timer.start() catch unreachable;

    // Warmup
    var i: u32 = 0;
    while (i < ctx.warmup) : (i += 1) {
        ctx.func();
    }

    // Actual benchmark
    timer.reset();
    i = 0;
    while (i < ctx.iterations) : (i += 1) {
        ctx.func();
    }
    const elapsed = timer.read();

    ctx.result.iterations = ctx.iterations;
    ctx.result.total_time_ns = elapsed;
    ctx.result.mean_ns = @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(ctx.iterations));
}

/// Scalability test - run with different thread counts
pub const ScalabilityTest = struct {
    name: []const u8,
    func: *const fn () void,
    thread_counts: []const usize,
    iterations_per_thread: u32,
    allocator: Allocator,

    pub fn init(
        allocator: Allocator,
        name: []const u8,
        func: *const fn () void,
        thread_counts: []const usize,
        iterations_per_thread: u32,
    ) ScalabilityTest {
        return .{
            .name = name,
            .func = func,
            .thread_counts = thread_counts,
            .iterations_per_thread = iterations_per_thread,
            .allocator = allocator,
        };
    }

    /// Run scalability test with all thread counts
    pub fn run(self: *const ScalabilityTest) !void {
        const stdout = std.fs.File.stdout();
        var buf: [512]u8 = undefined;

        const header = try std.fmt.bufPrint(&buf, "\n{s}=== Scalability Test: {s} ==={s}\n", .{
            bench.Formatter.BOLD,
            self.name,
            bench.Formatter.RESET,
        });
        try stdout.writeAll(header);

        for (self.thread_counts) |thread_count| {
            const config = ParallelConfig{
                .thread_count = thread_count,
                .iterations_per_thread = self.iterations_per_thread,
                .warmup_iterations = 5,
            };

            const pb = ParallelBenchmark.init(self.allocator, self.name, self.func, config);
            var result = try pb.run();
            defer result.deinit();

            const line = try std.fmt.bufPrint(&buf, "  {d} threads: {s}{d:.2} ops/sec total{s}, {d:.2} ops/sec/thread\n", .{
                thread_count,
                bench.Formatter.MAGENTA,
                result.ops_per_sec_total,
                bench.Formatter.RESET,
                result.ops_per_sec_per_thread,
            });
            try stdout.writeAll(line);
        }
    }
};
