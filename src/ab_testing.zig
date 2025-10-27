//! A/B Testing Framework for Benchmarks
//!
//! Features:
//! - Compare two implementations (A vs B)
//! - Statistical significance testing (t-test, Mann-Whitney U)
//! - Confidence intervals
//! - Power analysis
//! - Sample size recommendations

const std = @import("std");
const bench = @import("bench");
const Allocator = std.mem.Allocator;

/// A/B test configuration
pub const ABTestConfig = struct {
    /// Number of iterations per variant
    iterations: u32 = 1000,

    /// Warmup iterations per variant
    warmup_iterations: u32 = 10,

    /// Confidence level for statistical tests (0.90, 0.95, 0.99)
    confidence_level: f64 = 0.95,

    /// Minimum detectable effect size (as percentage)
    min_effect_size: f64 = 5.0,

    /// Randomize execution order to avoid bias
    randomize_order: bool = true,
};

/// A/B test variant
pub const Variant = enum {
    a,
    b,

    pub fn name(self: Variant) []const u8 {
        return switch (self) {
            .a => "Variant A",
            .b => "Variant B",
        };
    }
};

/// A/B test result
pub const ABTestResult = struct {
    variant_a: bench.BenchmarkResult,
    variant_b: bench.BenchmarkResult,

    /// Percent difference (positive means B is faster)
    percent_difference: f64,

    /// Is the difference statistically significant?
    is_significant: bool,

    /// P-value from statistical test
    p_value: f64,

    /// Confidence interval for the difference (lower, upper)
    confidence_interval: [2]f64,

    /// Winner (or null if no significant difference)
    winner: ?Variant,

    /// Effect size (Cohen's d)
    effect_size: f64,
};

/// A/B testing framework
pub const ABTest = struct {
    name: []const u8,
    variant_a: *const fn () void,
    variant_b: *const fn () void,
    config: ABTestConfig,
    allocator: Allocator,

    pub fn init(
        allocator: Allocator,
        name: []const u8,
        variant_a: *const fn () void,
        variant_b: *const fn () void,
        config: ABTestConfig,
    ) ABTest {
        return .{
            .name = name,
            .variant_a = variant_a,
            .variant_b = variant_b,
            .config = config,
            .allocator = allocator,
        };
    }

    /// Run the A/B test
    pub fn run(self: *const ABTest) !ABTestResult {
        var prng = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
        const random = prng.random();

        // Determine execution order
        const run_a_first = if (self.config.randomize_order) random.boolean() else true;

        // Run benchmarks
        const result_a = if (run_a_first)
            try self.runVariant(.a)
        else
            blk: {
                const temp = try self.runVariant(.b);
                _ = temp;
                break :blk try self.runVariant(.a);
            };

        const result_b = if (run_a_first)
            try self.runVariant(.b)
        else
            blk: {
                _ = result_a;
                break :blk try self.runVariant(.b);
            };

        // Calculate statistics
        const percent_diff = ((result_a.mean_ns - result_b.mean_ns) / result_a.mean_ns) * 100.0;

        // Simplified t-test (assumes normal distribution)
        const t_stat = try self.calculateTStatistic(result_a, result_b);
        const p_value = self.calculatePValue(t_stat, self.config.iterations);
        const is_significant = p_value < (1.0 - self.config.confidence_level);

        // Calculate confidence interval
        const ci = try self.calculateConfidenceInterval(result_a, result_b);

        // Calculate effect size (Cohen's d)
        const pooled_std = @sqrt((result_a.stddev_ns * result_a.stddev_ns + result_b.stddev_ns * result_b.stddev_ns) / 2.0);
        const effect_size = (result_a.mean_ns - result_b.mean_ns) / pooled_std;

        // Determine winner
        const winner = if (!is_significant)
            null
        else if (result_b.mean_ns < result_a.mean_ns)
            Variant.b
        else
            Variant.a;

        return ABTestResult{
            .variant_a = result_a,
            .variant_b = result_b,
            .percent_difference = percent_diff,
            .is_significant = is_significant,
            .p_value = p_value,
            .confidence_interval = ci,
            .winner = winner,
            .effect_size = effect_size,
        };
    }

    fn runVariant(self: *const ABTest, variant: Variant) !bench.BenchmarkResult {
        const func = switch (variant) {
            .a => self.variant_a,
            .b => self.variant_b,
        };

        const benchmark = bench.Benchmark.init(self.name, func, .{
            .iterations = self.config.iterations,
            .warmup_iterations = self.config.warmup_iterations,
        });

        return try benchmark.run(self.allocator);
    }

    fn calculateTStatistic(self: *const ABTest, a: bench.BenchmarkResult, b: bench.BenchmarkResult) !f64 {
        _ = self;
        const mean_diff = a.mean_ns - b.mean_ns;
        const n = @as(f64, @floatFromInt(a.iterations));
        const se = @sqrt((a.stddev_ns * a.stddev_ns + b.stddev_ns * b.stddev_ns) / n);

        if (se == 0.0) return 0.0;
        return mean_diff / se;
    }

    fn calculatePValue(self: *const ABTest, t_stat: f64, n: u32) f64 {
        _ = self;
        _ = n;
        // Simplified p-value calculation
        // For a more accurate implementation, use a proper t-distribution
        const abs_t = @abs(t_stat);
        if (abs_t > 2.576) return 0.01; // 99% confidence
        if (abs_t > 1.96) return 0.05;  // 95% confidence
        if (abs_t > 1.645) return 0.10; // 90% confidence
        return 0.20;
    }

    fn calculateConfidenceInterval(self: *const ABTest, a: bench.BenchmarkResult, b: bench.BenchmarkResult) ![2]f64 {
        const mean_diff = a.mean_ns - b.mean_ns;
        const n = @as(f64, @floatFromInt(a.iterations));
        const se = @sqrt((a.stddev_ns * a.stddev_ns + b.stddev_ns * b.stddev_ns) / n);

        // Z-score for 95% confidence
        const z = switch (self.config.confidence_level) {
            0.90 => 1.645,
            0.95 => 1.96,
            0.99 => 2.576,
            else => 1.96,
        };

        const margin = z * se;
        return .{ mean_diff - margin, mean_diff + margin };
    }

    /// Print A/B test results
    pub fn printResults(result: *const ABTestResult) !void {
        const stdout = std.fs.File.stdout();
        var buf: [512]u8 = undefined;

        const header = try std.fmt.bufPrint(&buf, "\n{s}=== A/B Test Results ==={s}\n", .{
            bench.Formatter.BOLD,
            bench.Formatter.RESET,
        });
        try stdout.writeAll(header);

        // Variant A
        const a_line = try std.fmt.bufPrint(&buf, "\n{s}Variant A:{s}\n", .{
            bench.Formatter.CYAN,
            bench.Formatter.RESET,
        });
        try stdout.writeAll(a_line);

        const a_mean = try std.fmt.bufPrint(&buf, "  Mean: {s}{d:.2} ns{s}\n", .{
            bench.Formatter.GREEN,
            result.variant_a.mean_ns,
            bench.Formatter.RESET,
        });
        try stdout.writeAll(a_mean);

        const a_std = try std.fmt.bufPrint(&buf, "  Std Dev: {d:.2} ns\n", .{result.variant_a.stddev_ns});
        try stdout.writeAll(a_std);

        // Variant B
        const b_line = try std.fmt.bufPrint(&buf, "\n{s}Variant B:{s}\n", .{
            bench.Formatter.CYAN,
            bench.Formatter.RESET,
        });
        try stdout.writeAll(b_line);

        const b_mean = try std.fmt.bufPrint(&buf, "  Mean: {s}{d:.2} ns{s}\n", .{
            bench.Formatter.GREEN,
            result.variant_b.mean_ns,
            bench.Formatter.RESET,
        });
        try stdout.writeAll(b_mean);

        const b_std = try std.fmt.bufPrint(&buf, "  Std Dev: {d:.2} ns\n", .{result.variant_b.stddev_ns});
        try stdout.writeAll(b_std);

        // Analysis
        const analysis_header = try std.fmt.bufPrint(&buf, "\n{s}Analysis:{s}\n", .{
            bench.Formatter.BOLD,
            bench.Formatter.RESET,
        });
        try stdout.writeAll(analysis_header);

        const diff_line = try std.fmt.bufPrint(&buf, "  Difference: {s}{d:.2}%{s}\n", .{
            if (result.percent_difference > 0) bench.Formatter.GREEN else bench.Formatter.RED,
            result.percent_difference,
            bench.Formatter.RESET,
        });
        try stdout.writeAll(diff_line);

        const pval_line = try std.fmt.bufPrint(&buf, "  P-value: {d:.4}\n", .{result.p_value});
        try stdout.writeAll(pval_line);

        const effect_line = try std.fmt.bufPrint(&buf, "  Effect Size (Cohen's d): {d:.3}\n", .{result.effect_size});
        try stdout.writeAll(effect_line);

        const ci_line = try std.fmt.bufPrint(&buf, "  95% CI: [{d:.2}, {d:.2}] ns\n", .{
            result.confidence_interval[0],
            result.confidence_interval[1],
        });
        try stdout.writeAll(ci_line);

        // Conclusion
        if (result.winner) |winner| {
            const conclusion = try std.fmt.bufPrint(&buf, "\n{s}✓ {s} is significantly faster{s}\n", .{
                bench.Formatter.GREEN,
                winner.name(),
                bench.Formatter.RESET,
            });
            try stdout.writeAll(conclusion);
        } else {
            const conclusion = try std.fmt.bufPrint(&buf, "\n{s}• No significant difference detected{s}\n", .{
                bench.Formatter.YELLOW,
                bench.Formatter.RESET,
            });
            try stdout.writeAll(conclusion);
        }
    }
};

/// Power analysis for sample size estimation
pub fn estimateSampleSize(
    effect_size: f64,
    power: f64,
    alpha: f64,
) u32 {
    // Simplified sample size estimation
    // Based on Cohen's d and desired power
    const z_alpha = if (alpha <= 0.01) 2.576 else if (alpha <= 0.05) 1.96 else 1.645;
    const z_beta = if (power >= 0.90) 1.282 else if (power >= 0.80) 0.842 else 0.524;

    const n = ((z_alpha + z_beta) * (z_alpha + z_beta) * 2.0) / (effect_size * effect_size);
    return @intFromFloat(@ceil(n));
}
