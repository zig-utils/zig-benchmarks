const std = @import("std");
const Timer = std.time.Timer;
const Allocator = std.mem.Allocator;
const bench = @import("bench.zig");

pub const AsyncBenchmark = struct {
    name: []const u8,
    func: *const fn () anyerror!void,
    opts: bench.BenchmarkOptions,

    pub fn init(name: []const u8, func: *const fn () anyerror!void) AsyncBenchmark {
        return .{
            .name = name,
            .func = func,
            .opts = .{},
        };
    }

    pub fn withOptions(name: []const u8, func: *const fn () anyerror!void, opts: bench.BenchmarkOptions) AsyncBenchmark {
        return .{
            .name = name,
            .func = func,
            .opts = opts,
        };
    }

    pub fn run(self: *const AsyncBenchmark, allocator: Allocator) !bench.BenchmarkResult {
        var samples = std.ArrayList(u64){};
        errdefer samples.deinit(allocator);

        // Warmup phase
        var i: u32 = 0;
        while (i < self.opts.warmup_iterations) : (i += 1) {
            try self.func();
        }

        // Benchmark phase
        var timer = try Timer.start();
        var total_time: u64 = 0;
        var iterations: u64 = 0;

        while (iterations < self.opts.max_iterations and total_time < self.opts.min_time_ns) {
            timer.reset();
            try self.func();
            const elapsed = timer.read();
            try samples.append(allocator, elapsed);
            total_time += elapsed;
            iterations += 1;

            if (iterations < self.opts.min_iterations) {
                continue;
            }
        }

        // Calculate statistics
        const mean_val = bench.Stats.mean(samples.items);
        const stddev_val = bench.Stats.stddev(samples.items, mean_val);

        var samples_copy = try samples.clone(allocator);
        defer samples_copy.deinit(allocator);

        const p50 = bench.Stats.percentile(samples_copy.items, 0.50);
        const p75 = bench.Stats.percentile(samples_copy.items, 0.75);
        const p99 = bench.Stats.percentile(samples_copy.items, 0.99);

        const min_val = bench.Stats.min(samples.items);
        const max_val = bench.Stats.max(samples.items);

        const ops_per_sec = if (mean_val > 0) 1_000_000_000.0 / mean_val else 0.0;

        return bench.BenchmarkResult{
            .name = self.name,
            .samples = samples,
            .mean = mean_val,
            .stddev = stddev_val,
            .min = min_val,
            .max = max_val,
            .p50 = p50,
            .p75 = p75,
            .p99 = p99,
            .ops_per_sec = ops_per_sec,
            .iterations = iterations,
        };
    }
};

pub const AsyncBenchmarkSuite = struct {
    benchmarks: std.ArrayList(AsyncBenchmark),
    allocator: Allocator,

    pub fn init(allocator: Allocator) AsyncBenchmarkSuite {
        return .{
            .benchmarks = std.ArrayList(AsyncBenchmark){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *AsyncBenchmarkSuite) void {
        self.benchmarks.deinit(self.allocator);
    }

    pub fn add(self: *AsyncBenchmarkSuite, name: []const u8, func: *const fn () anyerror!void) !void {
        try self.benchmarks.append(self.allocator, AsyncBenchmark.init(name, func));
    }

    pub fn addWithOptions(self: *AsyncBenchmarkSuite, name: []const u8, func: *const fn () anyerror!void, opts: bench.BenchmarkOptions) !void {
        try self.benchmarks.append(self.allocator, AsyncBenchmark.withOptions(name, func, opts));
    }

    pub fn run(self: *AsyncBenchmarkSuite) !void {
        const stdout = std.io.getStdOut().writer();
        const formatter = bench.Formatter{};

        try formatter.printHeader(stdout);

        var results = std.ArrayList(bench.BenchmarkResult){};
        defer {
            for (results.items) |*result| {
                result.deinit();
            }
            results.deinit(self.allocator);
        }

        for (self.benchmarks.items) |*benchmark| {
            try formatter.printBenchmarkStart(stdout, benchmark.name);
            const result = try benchmark.run(self.allocator);
            try results.append(self.allocator, result);
            try formatter.printResult(stdout, &result);
        }

        try formatter.printSummary(stdout, results.items);
    }
};
