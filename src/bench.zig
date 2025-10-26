const std = @import("std");
const Timer = std.time.Timer;
const Allocator = std.mem.Allocator;

pub const BenchmarkOptions = struct {
    warmup_iterations: u32 = 5,
    min_iterations: u32 = 10,
    max_iterations: u32 = 10_000,
    min_time_ns: u64 = 1_000_000_000, // 1 second
    baseline: ?[]const u8 = null,
};

pub const BenchmarkResult = struct {
    name: []const u8,
    samples: std.ArrayList(u64),
    mean: f64,
    stddev: f64,
    min: u64,
    max: u64,
    p50: u64,
    p75: u64,
    p99: u64,
    ops_per_sec: f64,
    iterations: u64,

    pub fn deinit(self: *BenchmarkResult) void {
        self.samples.deinit();
    }
};

pub const Stats = struct {
    pub fn mean(samples: []const u64) f64 {
        if (samples.len == 0) return 0.0;
        var sum: f64 = 0.0;
        for (samples) |sample| {
            sum += @as(f64, @floatFromInt(sample));
        }
        return sum / @as(f64, @floatFromInt(samples.len));
    }

    pub fn stddev(samples: []const u64, mean_val: f64) f64 {
        if (samples.len <= 1) return 0.0;
        var variance: f64 = 0.0;
        for (samples) |sample| {
            const diff = @as(f64, @floatFromInt(sample)) - mean_val;
            variance += diff * diff;
        }
        return @sqrt(variance / @as(f64, @floatFromInt(samples.len - 1)));
    }

    pub fn percentile(samples: []u64, p: f64) u64 {
        if (samples.len == 0) return 0;
        std.mem.sort(u64, samples, {}, std.sort.asc(u64));
        const index = @as(usize, @intFromFloat(@as(f64, @floatFromInt(samples.len)) * p));
        return samples[@min(index, samples.len - 1)];
    }

    pub fn min(samples: []const u64) u64 {
        if (samples.len == 0) return 0;
        var min_val = samples[0];
        for (samples[1..]) |sample| {
            if (sample < min_val) min_val = sample;
        }
        return min_val;
    }

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

    pub fn run(self: *const Benchmark, allocator: Allocator) !BenchmarkResult {
        var samples = std.ArrayList(u64){};
        errdefer samples.deinit(allocator);

        // Warmup phase
        var i: u32 = 0;
        while (i < self.opts.warmup_iterations) : (i += 1) {
            self.func();
        }

        // Benchmark phase
        var timer = try Timer.start();
        var total_time: u64 = 0;
        var iterations: u64 = 0;

        while (iterations < self.opts.max_iterations and total_time < self.opts.min_time_ns) {
            timer.reset();
            self.func();
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

pub const BenchmarkSuite = struct {
    benchmarks: std.ArrayList(Benchmark),
    allocator: Allocator,

    pub fn init(allocator: Allocator) BenchmarkSuite {
        return .{
            .benchmarks = std.ArrayList(Benchmark){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *BenchmarkSuite) void {
        self.benchmarks.deinit(self.allocator);
    }

    pub fn add(self: *BenchmarkSuite, name: []const u8, func: *const fn () void) !void {
        try self.benchmarks.append(self.allocator, Benchmark.init(name, func));
    }

    pub fn addWithOptions(self: *BenchmarkSuite, name: []const u8, func: *const fn () void, opts: BenchmarkOptions) !void {
        try self.benchmarks.append(self.allocator, Benchmark.withOptions(name, func, opts));
    }

    pub fn run(self: *BenchmarkSuite) !void {
        var stdout_buf: [8192]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
        const stdout = &stdout_writer.interface;

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
            try formatter.printBenchmarkStart(stdout, benchmark.name);
            const result = try benchmark.run(self.allocator);
            try results.append(self.allocator, result);
            try formatter.printResult(stdout, &result);
        }

        try formatter.printSummary(stdout, results.items);
    }
};

pub const Formatter = struct {
    // ANSI color codes
    const RESET = "\x1b[0m";
    const BOLD = "\x1b[1m";
    const DIM = "\x1b[2m";
    const CYAN = "\x1b[36m";
    const GREEN = "\x1b[32m";
    const YELLOW = "\x1b[33m";
    const BLUE = "\x1b[34m";
    const MAGENTA = "\x1b[35m";

    pub fn printHeader(self: Formatter, writer: anytype) !void {
        _ = self;
        try writer.print("\n{s}{s}Zig Benchmark Suite{s}\n", .{ BOLD, CYAN, RESET });
        try writer.print("{s}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{s}\n\n", .{ DIM, RESET });
    }

    pub fn printBenchmarkStart(self: Formatter, writer: anytype, name: []const u8) !void {
        _ = self;
        try writer.print("{s}▶{s} Running: {s}{s}{s}\n", .{ BLUE, RESET, BOLD, name, RESET });
    }

    pub fn printResult(self: Formatter, writer: anytype, result: *const BenchmarkResult) !void {
        _ = self;

        try writer.print("  {s}Iterations:{s} {d}\n", .{ DIM, RESET, result.iterations });
        try writer.print("  {s}Mean:{s}       {s}{s}{s}\n", .{ DIM, RESET, GREEN, formatTime(result.mean), RESET });
        try writer.print("  {s}Std Dev:{s}    {s}\n", .{ DIM, RESET, formatTime(result.stddev) });
        try writer.print("  {s}Min:{s}        {s}\n", .{ DIM, RESET, formatTime(@floatFromInt(result.min)) });
        try writer.print("  {s}Max:{s}        {s}\n", .{ DIM, RESET, formatTime(@floatFromInt(result.max)) });
        try writer.print("  {s}P50:{s}        {s}\n", .{ DIM, RESET, formatTime(@floatFromInt(result.p50)) });
        try writer.print("  {s}P75:{s}        {s}\n", .{ DIM, RESET, formatTime(@floatFromInt(result.p75)) });
        try writer.print("  {s}P99:{s}        {s}\n", .{ DIM, RESET, formatTime(@floatFromInt(result.p99)) });
        try writer.print("  {s}Ops/sec:{s}    {s}{s}{s}\n\n", .{ DIM, RESET, MAGENTA, formatOps(result.ops_per_sec), RESET });
    }

    pub fn printSummary(self: Formatter, writer: anytype, results: []const BenchmarkResult) !void {
        _ = self;
        if (results.len == 0) return;

        try writer.print("{s}{s}Summary{s}\n", .{ BOLD, CYAN, RESET });
        try writer.print("{s}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{s}\n", .{ DIM, RESET });

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
                try writer.print("  {s}✓{s} {s}{s}{s} - {s}fastest{s}\n", .{
                    GREEN,
                    RESET,
                    BOLD,
                    result.name,
                    RESET,
                    GREEN,
                    RESET,
                });
            } else {
                try writer.print("  {s}•{s} {s} - {s}{d:.2}x{s} slower\n", .{
                    YELLOW,
                    RESET,
                    result.name,
                    YELLOW,
                    relative,
                    RESET,
                });
            }
        }
        try writer.print("\n");
    }

    fn formatTime(ns: f64) [64]u8 {
        var buf: [64]u8 = undefined;
        const formatted = if (ns < 1_000)
            std.fmt.bufPrint(&buf, "{d:.2} ns", .{ns}) catch unreachable
        else if (ns < 1_000_000)
            std.fmt.bufPrint(&buf, "{d:.2} µs", .{ns / 1_000}) catch unreachable
        else if (ns < 1_000_000_000)
            std.fmt.bufPrint(&buf, "{d:.2} ms", .{ns / 1_000_000}) catch unreachable
        else
            std.fmt.bufPrint(&buf, "{d:.2} s", .{ns / 1_000_000_000}) catch unreachable;

        var result: [64]u8 = undefined;
        @memcpy(result[0..formatted.len], formatted);
        return result;
    }

    fn formatOps(ops: f64) [64]u8 {
        var buf: [64]u8 = undefined;
        const formatted = if (ops < 1_000)
            std.fmt.bufPrint(&buf, "{d:.2}", .{ops}) catch unreachable
        else if (ops < 1_000_000)
            std.fmt.bufPrint(&buf, "{d:.2}k", .{ops / 1_000}) catch unreachable
        else if (ops < 1_000_000_000)
            std.fmt.bufPrint(&buf, "{d:.2}M", .{ops / 1_000_000}) catch unreachable
        else
            std.fmt.bufPrint(&buf, "{d:.2}B", .{ops / 1_000_000_000}) catch unreachable;

        var result: [64]u8 = undefined;
        @memcpy(result[0..formatted.len], formatted);
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

    pub fn addWithOptions(self: *AsyncBenchmarkSuite, name: []const u8, func: *const fn () anyerror!void, opts: BenchmarkOptions) !void {
        try self.benchmarks.append(self.allocator, AsyncBenchmark.withOptions(name, func, opts));
    }

    pub fn run(self: *AsyncBenchmarkSuite) !void {
        var stdout_buf: [8192]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
        const stdout = &stdout_writer.interface;

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
            try formatter.printBenchmarkStart(stdout, benchmark.name);
            const result = try benchmark.run(self.allocator);
            try results.append(self.allocator, result);
            try formatter.printResult(stdout, &result);
        }

        try formatter.printSummary(stdout, results.items);
    }
};
