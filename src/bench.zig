//! Zig Bench - A modern, performant benchmark framework for Zig
//!
//! This module provides a comprehensive benchmarking framework with:
//! - High-precision timing using std.time.Timer
//! - Statistical analysis (mean, stddev, percentiles)
//! - Beautiful CLI output with colors
//! - Flexible configuration options
//! - Support for async/error-handling functions
//! - Baseline comparison and filtering
//! - Custom allocator support

const std = @import("std");
const Timer = std.time.Timer;
const Allocator = std.mem.Allocator;

/// Configuration options for individual benchmarks
pub const BenchmarkOptions = struct {
    /// Number of warmup iterations to run before measuring (default: 5)
    /// Warmup helps stabilize CPU caches and frequency scaling
    warmup_iterations: u32 = 5,

    /// Minimum number of iterations to execute (default: 10)
    /// Ensures enough samples for statistical analysis
    min_iterations: u32 = 10,

    /// Maximum number of iterations to execute (default: 10,000)
    /// Prevents extremely fast operations from running too long
    max_iterations: u32 = 10_000,

    /// Minimum time to run benchmarks in nanoseconds (default: 1 second)
    /// Benchmarks continue until this time elapses AND min_iterations are met
    min_time_ns: u64 = 1_000_000_000,

    /// Optional baseline file path for comparison (reserved for future use)
    baseline: ?[]const u8 = null,

    /// Optional filter pattern to match benchmark names
    /// Only benchmarks matching this substring will run
    filter: ?[]const u8 = null,
};

/// Results from a benchmark run, containing timing samples and statistical analysis
pub const BenchmarkResult = struct {
    /// Name of the benchmark
    name: []const u8,

    /// Raw timing samples in nanoseconds
    samples: std.ArrayList(u64),

    /// Allocator used for samples
    allocator: Allocator,

    /// Mean (average) execution time in nanoseconds
    mean: f64,

    /// Standard deviation of execution times
    stddev: f64,

    /// Minimum execution time in nanoseconds
    min: u64,

    /// Maximum execution time in nanoseconds
    max: u64,

    /// 50th percentile (median) in nanoseconds
    p50: u64,

    /// 75th percentile in nanoseconds
    p75: u64,

    /// 99th percentile in nanoseconds
    p99: u64,

    /// Operations per second (1e9 / mean)
    ops_per_sec: f64,

    /// Total number of iterations executed
    iterations: u64,

    /// Free the samples ArrayList
    pub fn deinit(self: *BenchmarkResult) void {
        self.samples.deinit(self.allocator);
    }

    /// Export this result as a JSON string (legacy format)
    /// Note: Use the export module for more advanced export features
    pub fn toJson(self: *const BenchmarkResult, allocator: Allocator) ![]u8 {
        var string = std.ArrayList(u8){};
        defer string.deinit(allocator);

        var writer = string.writer(allocator);
        try writer.print("{{\"name\":\"{s}\",\"mean\":{d:.2},\"stddev\":{d:.2},\"min\":{d},\"max\":{d},\"p50\":{d},\"p75\":{d},\"p99\":{d},\"ops_per_sec\":{d:.2},\"iterations\":{d}}}", .{
            self.name,
            self.mean,
            self.stddev,
            self.min,
            self.max,
            self.p50,
            self.p75,
            self.p99,
            self.ops_per_sec,
            self.iterations,
        });

        return string.toOwnedSlice(allocator);
    }
};

/// Statistical analysis functions for benchmark samples
pub const Stats = struct {
    /// Calculate the arithmetic mean (average) of samples
    /// Returns 0.0 for empty samples
    pub fn mean(samples: []const u64) f64 {
        if (samples.len == 0) return 0.0;
        var sum: f64 = 0.0;
        for (samples) |sample| {
            sum += @as(f64, @floatFromInt(sample));
        }
        return sum / @as(f64, @floatFromInt(samples.len));
    }

    /// Calculate the standard deviation using Bessel's correction (n-1)
    /// Returns 0.0 for samples with length <= 1
    pub fn stddev(samples: []const u64, mean_val: f64) f64 {
        if (samples.len <= 1) return 0.0;
        var variance: f64 = 0.0;
        for (samples) |sample| {
            const diff = @as(f64, @floatFromInt(sample)) - mean_val;
            variance += diff * diff;
        }
        return @sqrt(variance / @as(f64, @floatFromInt(samples.len - 1)));
    }

    /// Calculate a percentile value (p should be between 0.0 and 1.0)
    /// Note: This sorts the samples array in-place
    /// Examples: p=0.5 for median (P50), p=0.99 for P99
    pub fn percentile(samples: []u64, p: f64) u64 {
        if (samples.len == 0) return 0;
        std.mem.sort(u64, samples, {}, std.sort.asc(u64));
        const index = @as(usize, @intFromFloat(@as(f64, @floatFromInt(samples.len)) * p));
        return samples[@min(index, samples.len - 1)];
    }

    /// Find the minimum value in samples
    /// Returns 0 for empty samples
    pub fn min(samples: []const u64) u64 {
        if (samples.len == 0) return 0;
        var min_val = samples[0];
        for (samples[1..]) |sample| {
            if (sample < min_val) min_val = sample;
        }
        return min_val;
    }

    /// Find the maximum value in samples
    /// Returns 0 for empty samples
    pub fn max(samples: []const u64) u64 {
        if (samples.len == 0) return 0;
        var max_val = samples[0];
        for (samples[1..]) |sample| {
            if (sample > max_val) max_val = sample;
        }
        return max_val;
    }
};

pub const Benchmark = struct {
    name: []const u8,
    func: *const fn () void,
    opts: BenchmarkOptions,
    allocator_func: ?*const fn (Allocator) void = null,

    pub fn init(name: []const u8, func: *const fn () void) Benchmark {
        return .{
            .name = name,
            .func = func,
            .opts = .{},
        };
    }

    pub fn withOptions(name: []const u8, func: *const fn () void, opts: BenchmarkOptions) Benchmark {
        return .{
            .name = name,
            .func = func,
            .opts = opts,
        };
    }

    pub fn withAllocator(name: []const u8, func: *const fn (Allocator) void) Benchmark {
        return .{
            .name = name,
            .func = undefined,
            .opts = .{},
            .allocator_func = func,
        };
    }

    pub fn withAllocatorAndOptions(name: []const u8, func: *const fn (Allocator) void, opts: BenchmarkOptions) Benchmark {
        return .{
            .name = name,
            .func = undefined,
            .opts = opts,
            .allocator_func = func,
        };
    }

    pub fn run(self: *const Benchmark, allocator: Allocator) !BenchmarkResult {
        var samples = std.ArrayList(u64){};
        errdefer samples.deinit(allocator);

        const is_allocator_func = self.allocator_func != null;

        // Warmup phase
        var i: u32 = 0;
        while (i < self.opts.warmup_iterations) : (i += 1) {
            if (is_allocator_func) {
                self.allocator_func.?(allocator);
            } else {
                self.func();
            }
        }

        // Benchmark phase
        var timer = try Timer.start();
        var total_time: u64 = 0;
        var iterations: u64 = 0;

        while (iterations < self.opts.max_iterations and total_time < self.opts.min_time_ns) {
            timer.reset();
            if (is_allocator_func) {
                self.allocator_func.?(allocator);
            } else {
                self.func();
            }
            const elapsed = timer.read();
            try samples.append(allocator, elapsed);
            total_time += elapsed;
            iterations += 1;

            // Ensure we run at least min_iterations
            if (iterations < self.opts.min_iterations) {
                continue;
            }
        }

        // Calculate statistics
        const mean_val = Stats.mean(samples.items);
        const stddev_val = Stats.stddev(samples.items, mean_val);

        // Create a copy for percentile calculations (they sort in-place)
        var samples_copy = try samples.clone(allocator);
        defer samples_copy.deinit(allocator);

        const p50 = Stats.percentile(samples_copy.items, 0.50);
        const p75 = Stats.percentile(samples_copy.items, 0.75);
        const p99 = Stats.percentile(samples_copy.items, 0.99);

        const min_val = Stats.min(samples.items);
        const max_val = Stats.max(samples.items);

        // Calculate operations per second
        const ops_per_sec = if (mean_val > 0) 1_000_000_000.0 / mean_val else 0.0;

        return BenchmarkResult{
            .name = self.name,
            .samples = samples,
            .allocator = allocator,
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

/// A suite of benchmarks to run together
/// Manages multiple benchmarks and provides comparison features
pub const BenchmarkSuite = struct {
    /// List of benchmarks to run
    benchmarks: std.ArrayList(Benchmark),

    /// Allocator for managing benchmarks
    allocator: Allocator,

    /// Optional filter pattern - only benchmarks matching this substring will run
    filter: ?[]const u8 = null,

    /// Optional baseline file path for saving results
    baseline_path: ?[]const u8 = null,

    /// Initialize a new benchmark suite
    pub fn init(allocator: Allocator) BenchmarkSuite {
        return .{
            .benchmarks = std.ArrayList(Benchmark){},
            .allocator = allocator,
        };
    }

    /// Clean up the suite and free resources
    pub fn deinit(self: *BenchmarkSuite) void {
        self.benchmarks.deinit(self.allocator);
    }

    /// Add a simple benchmark function to the suite
    /// The function should take no arguments and return void
    pub fn add(self: *BenchmarkSuite, name: []const u8, func: *const fn () void) !void {
        try self.benchmarks.append(self.allocator, Benchmark.init(name, func));
    }

    /// Add a benchmark with custom options (warmup, iterations, timing)
    pub fn addWithOptions(self: *BenchmarkSuite, name: []const u8, func: *const fn () void, opts: BenchmarkOptions) !void {
        try self.benchmarks.append(self.allocator, Benchmark.withOptions(name, func, opts));
    }

    /// Add a benchmark that requires an allocator parameter
    /// Useful for testing allocation-heavy operations
    pub fn addWithAllocator(self: *BenchmarkSuite, name: []const u8, func: *const fn (Allocator) void) !void {
        try self.benchmarks.append(self.allocator, Benchmark.withAllocator(name, func));
    }

    /// Add a benchmark with both custom allocator and options
    pub fn addWithAllocatorAndOptions(self: *BenchmarkSuite, name: []const u8, func: *const fn (Allocator) void, opts: BenchmarkOptions) !void {
        try self.benchmarks.append(self.allocator, Benchmark.withAllocatorAndOptions(name, func, opts));
    }

    pub fn setFilter(self: *BenchmarkSuite, filter: []const u8) void {
        self.filter = filter;
    }

    pub fn setBaseline(self: *BenchmarkSuite, path: []const u8) void {
        self.baseline_path = path;
    }

    fn matchesFilter(self: *const BenchmarkSuite, name: []const u8) bool {
        if (self.filter == null) return true;
        // Simple substring match for now
        return std.mem.indexOf(u8, name, self.filter.?) != null;
    }

    pub fn saveBaseline(self: *BenchmarkSuite, results: []const BenchmarkResult, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        try file.writeAll("[\n");
        for (results, 0..) |result, i| {
            const json = try result.toJson(self.allocator);
            defer self.allocator.free(json);
            try file.writeAll("  ");
            try file.writeAll(json);
            if (i < results.len - 1) {
                try file.writeAll(",\n");
            } else {
                try file.writeAll("\n");
            }
        }
        try file.writeAll("]\n");
    }

    pub fn run(self: *BenchmarkSuite) !void {
        const stdout = std.fs.File.stdout();
        const formatter = Formatter{};

        try formatter.printHeader(stdout);

        var results = std.ArrayList(BenchmarkResult){};
        defer {
            for (results.items) |*result| {
                result.deinit();
            }
            results.deinit(self.allocator);
        }

        for (self.benchmarks.items) |*benchmark| {
            // Skip if doesn't match filter
            if (!self.matchesFilter(benchmark.name)) {
                continue;
            }

            try formatter.printBenchmarkStart(stdout, benchmark.name);
            const result = try benchmark.run(self.allocator);
            try results.append(self.allocator, result);
            try formatter.printResult(stdout, &result);
        }

        if (results.items.len > 0) {
            try formatter.printSummary(stdout, results.items);

            // Save baseline if path is set
            if (self.baseline_path) |path| {
                try self.saveBaseline(results.items, path);
                var buf: [256]u8 = undefined;
                const msg = try std.fmt.bufPrint(&buf, "\n{s}Baseline saved to: {s}{s}\n", .{ Formatter.DIM, path, Formatter.RESET });
                try stdout.writeAll(msg);
            }
        }
    }
};

/// Formatter for beautiful CLI output with ANSI colors and formatting
pub const Formatter = struct {
    // ANSI color codes for terminal output
    pub const RESET = "\x1b[0m"; // Reset all attributes
    pub const BOLD = "\x1b[1m"; // Bold text
    pub const DIM = "\x1b[2m"; // Dimmed text
    pub const CYAN = "\x1b[36m"; // Cyan color
    pub const GREEN = "\x1b[32m"; // Green color (used for success/fast)
    pub const YELLOW = "\x1b[33m"; // Yellow color (used for warnings/comparisons)
    pub const BLUE = "\x1b[34m"; // Blue color (used for info)
    pub const MAGENTA = "\x1b[35m"; // Magenta color

    /// Print the benchmark suite header
    pub fn printHeader(self: Formatter, file: std.fs.File) !void {
        _ = self;
        var buf: [256]u8 = undefined;
        const msg1 = try std.fmt.bufPrint(&buf, "\n{s}{s}Zig Benchmark Suite{s}\n", .{ BOLD, CYAN, RESET });
        try file.writeAll(msg1);
        const msg2 = try std.fmt.bufPrint(&buf, "{s}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{s}\n\n", .{ DIM, RESET });
        try file.writeAll(msg2);
    }

    pub fn printBenchmarkStart(self: Formatter, file: std.fs.File, name: []const u8) !void {
        _ = self;
        var buf: [512]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "{s}▶{s} Running: {s}{s}{s}\n", .{ BLUE, RESET, BOLD, name, RESET });
        try file.writeAll(msg);
    }

    pub fn printResult(self: Formatter, file: std.fs.File, result: *const BenchmarkResult) !void {
        _ = self;
        var buf: [512]u8 = undefined;

        var msg = try std.fmt.bufPrint(&buf, "  {s}Iterations:{s} {d}\n", .{ DIM, RESET, result.iterations });
        try file.writeAll(msg);
        msg = try std.fmt.bufPrint(&buf, "  {s}Mean:{s}       {s}{s}{s}\n", .{ DIM, RESET, GREEN, formatTime(result.mean).slice(), RESET });
        try file.writeAll(msg);
        msg = try std.fmt.bufPrint(&buf, "  {s}Std Dev:{s}    {s}\n", .{ DIM, RESET, formatTime(result.stddev).slice() });
        try file.writeAll(msg);
        msg = try std.fmt.bufPrint(&buf, "  {s}Min:{s}        {s}\n", .{ DIM, RESET, formatTime(@floatFromInt(result.min)).slice() });
        try file.writeAll(msg);
        msg = try std.fmt.bufPrint(&buf, "  {s}Max:{s}        {s}\n", .{ DIM, RESET, formatTime(@floatFromInt(result.max)).slice() });
        try file.writeAll(msg);
        msg = try std.fmt.bufPrint(&buf, "  {s}P50:{s}        {s}\n", .{ DIM, RESET, formatTime(@floatFromInt(result.p50)).slice() });
        try file.writeAll(msg);
        msg = try std.fmt.bufPrint(&buf, "  {s}P75:{s}        {s}\n", .{ DIM, RESET, formatTime(@floatFromInt(result.p75)).slice() });
        try file.writeAll(msg);
        msg = try std.fmt.bufPrint(&buf, "  {s}P99:{s}        {s}\n", .{ DIM, RESET, formatTime(@floatFromInt(result.p99)).slice() });
        try file.writeAll(msg);
        msg = try std.fmt.bufPrint(&buf, "  {s}Ops/sec:{s}    {s}{s}{s}\n\n", .{ DIM, RESET, MAGENTA, formatOps(result.ops_per_sec).slice(), RESET });
        try file.writeAll(msg);
    }

    pub fn printSummary(self: Formatter, file: std.fs.File, results: []const BenchmarkResult) !void {
        _ = self;
        if (results.len == 0) return;

        var buf: [512]u8 = undefined;
        var msg = try std.fmt.bufPrint(&buf, "{s}{s}Summary{s}\n", .{ BOLD, CYAN, RESET });
        try file.writeAll(msg);
        msg = try std.fmt.bufPrint(&buf, "{s}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{s}\n", .{ DIM, RESET });
        try file.writeAll(msg);

        // Find the fastest benchmark
        var fastest_idx: usize = 0;
        var fastest_mean = results[0].mean;
        for (results, 0..) |result, i| {
            if (result.mean < fastest_mean) {
                fastest_mean = result.mean;
                fastest_idx = i;
            }
        }

        for (results, 0..) |result, i| {
            const is_fastest = i == fastest_idx;
            const relative = result.mean / fastest_mean;

            if (is_fastest) {
                msg = try std.fmt.bufPrint(&buf, "  {s}✓{s} {s}{s}{s} - {s}fastest{s}\n", .{
                    GREEN,
                    RESET,
                    BOLD,
                    result.name,
                    RESET,
                    GREEN,
                    RESET,
                });
                try file.writeAll(msg);
            } else {
                msg = try std.fmt.bufPrint(&buf, "  {s}•{s} {s} - {s}{d:.2}x{s} slower\n", .{
                    YELLOW,
                    RESET,
                    result.name,
                    YELLOW,
                    relative,
                    RESET,
                });
                try file.writeAll(msg);
            }
        }
        try file.writeAll("\n");
    }

    const FormattedValue = struct {
        buf: [64]u8,
        len: usize,

        pub fn slice(self: *const FormattedValue) []const u8 {
            return self.buf[0..self.len];
        }
    };

    fn formatTime(ns: f64) FormattedValue {
        var result: FormattedValue = .{ .buf = undefined, .len = 0 };
        const formatted = if (ns < 1_000)
            std.fmt.bufPrint(&result.buf, "{d:.2} ns", .{ns}) catch unreachable
        else if (ns < 1_000_000)
            std.fmt.bufPrint(&result.buf, "{d:.2} µs", .{ns / 1_000}) catch unreachable
        else if (ns < 1_000_000_000)
            std.fmt.bufPrint(&result.buf, "{d:.2} ms", .{ns / 1_000_000}) catch unreachable
        else
            std.fmt.bufPrint(&result.buf, "{d:.2} s", .{ns / 1_000_000_000}) catch unreachable;

        result.len = formatted.len;
        return result;
    }

    fn formatOps(ops: f64) FormattedValue {
        var result: FormattedValue = .{ .buf = undefined, .len = 0 };
        const formatted = if (ops < 1_000)
            std.fmt.bufPrint(&result.buf, "{d:.2}", .{ops}) catch unreachable
        else if (ops < 1_000_000)
            std.fmt.bufPrint(&result.buf, "{d:.2}k", .{ops / 1_000}) catch unreachable
        else if (ops < 1_000_000_000)
            std.fmt.bufPrint(&result.buf, "{d:.2}M", .{ops / 1_000_000}) catch unreachable
        else
            std.fmt.bufPrint(&result.buf, "{d:.2}B", .{ops / 1_000_000_000}) catch unreachable;

        result.len = formatted.len;
        return result;
    }
};

// Convenience functions for quick benchmarking
pub fn bench(name: []const u8, func: *const fn () void) !void {
    const allocator = std.heap.page_allocator;
    var suite = BenchmarkSuite.init(allocator);
    defer suite.deinit();

    try suite.add(name, func);
    try suite.run();
}

pub fn benchWithOptions(name: []const u8, func: *const fn () void, opts: BenchmarkOptions) !void {
    const allocator = std.heap.page_allocator;
    var suite = BenchmarkSuite.init(allocator);
    defer suite.deinit();

    try suite.addWithOptions(name, func, opts);
    try suite.run();
}

// Async Benchmark Support
pub const AsyncBenchmark = struct {
    name: []const u8,
    func: *const fn () anyerror!void,
    opts: BenchmarkOptions,

    pub fn init(name: []const u8, func: *const fn () anyerror!void) AsyncBenchmark {
        return .{
            .name = name,
            .func = func,
            .opts = .{},
        };
    }

    pub fn withOptions(name: []const u8, func: *const fn () anyerror!void, opts: BenchmarkOptions) AsyncBenchmark {
        return .{
            .name = name,
            .func = func,
            .opts = opts,
        };
    }

    pub fn run(self: *const AsyncBenchmark, allocator: Allocator) !BenchmarkResult {
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
        const mean_val = Stats.mean(samples.items);
        const stddev_val = Stats.stddev(samples.items, mean_val);

        var samples_copy = try samples.clone(allocator);
        defer samples_copy.deinit(allocator);

        const p50 = Stats.percentile(samples_copy.items, 0.50);
        const p75 = Stats.percentile(samples_copy.items, 0.75);
        const p99 = Stats.percentile(samples_copy.items, 0.99);

        const min_val = Stats.min(samples.items);
        const max_val = Stats.max(samples.items);

        const ops_per_sec = if (mean_val > 0) 1_000_000_000.0 / mean_val else 0.0;

        return BenchmarkResult{
            .name = self.name,
            .samples = samples,
            .allocator = allocator,
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
    filter: ?[]const u8 = null,
    baseline_path: ?[]const u8 = null,

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

    pub fn addWithOptions(self: *AsyncBenchmarkSuite, name: []const u8, func: *const fn () anyerror!void, opts: BenchmarkOptions) !void {
        try self.benchmarks.append(self.allocator, AsyncBenchmark.withOptions(name, func, opts));
    }

    pub fn setFilter(self: *AsyncBenchmarkSuite, filter: []const u8) void {
        self.filter = filter;
    }

    pub fn setBaseline(self: *AsyncBenchmarkSuite, path: []const u8) void {
        self.baseline_path = path;
    }

    fn matchesFilter(self: *const AsyncBenchmarkSuite, name: []const u8) bool {
        if (self.filter == null) return true;
        return std.mem.indexOf(u8, name, self.filter.?) != null;
    }

    pub fn saveBaseline(self: *AsyncBenchmarkSuite, results: []const BenchmarkResult, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        try file.writeAll("[\n");
        for (results, 0..) |result, i| {
            const json = try result.toJson(self.allocator);
            defer self.allocator.free(json);
            try file.writeAll("  ");
            try file.writeAll(json);
            if (i < results.len - 1) {
                try file.writeAll(",\n");
            } else {
                try file.writeAll("\n");
            }
        }
        try file.writeAll("]\n");
    }

    pub fn run(self: *AsyncBenchmarkSuite) !void {
        const stdout = std.fs.File.stdout();
        const formatter = Formatter{};

        try formatter.printHeader(stdout);

        var results = std.ArrayList(BenchmarkResult){};
        defer {
            for (results.items) |*result| {
                result.deinit();
            }
            results.deinit(self.allocator);
        }

        for (self.benchmarks.items) |*benchmark| {
            if (!self.matchesFilter(benchmark.name)) {
                continue;
            }

            try formatter.printBenchmarkStart(stdout, benchmark.name);
            const result = try benchmark.run(self.allocator);
            try results.append(self.allocator, result);
            try formatter.printResult(stdout, &result);
        }

        if (results.items.len > 0) {
            try formatter.printSummary(stdout, results.items);

            if (self.baseline_path) |path| {
                try self.saveBaseline(results.items, path);
                var buf: [256]u8 = undefined;
                const msg = try std.fmt.bufPrint(&buf, "\n{s}Baseline saved to: {s}{s}\n", .{ Formatter.DIM, path, Formatter.RESET });
                try stdout.writeAll(msg);
            }
        }
    }
};
