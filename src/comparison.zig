//! Comparison module - Compare benchmark results against saved baselines
//!
//! Features:
//! - Load baseline results from JSON files
//! - Compare current vs baseline with percentage change
//! - Automatic regression detection with configurable thresholds
//! - Colored output showing improvements and regressions

const std = @import("std");
const bench = @import("bench");
const Allocator = std.mem.Allocator;
const BenchmarkResult = bench.BenchmarkResult;

/// Result of comparing a benchmark against its baseline
pub const ComparisonResult = struct {
    /// Name of the benchmark
    name: []const u8,

    /// Current mean execution time in nanoseconds
    current_mean: f64,

    /// Baseline mean execution time in nanoseconds
    baseline_mean: f64,

    /// Percentage change (positive = slower, negative = faster)
    change_percent: f64,

    /// Whether this is considered a performance regression
    is_regression: bool,

    /// Threshold percentage for regression detection (default: 10%)
    regression_threshold: f64 = 10.0,

    pub fn format(self: ComparisonResult, allocator: Allocator) ![]u8 {
        var buf = std.ArrayList(u8){};
        defer buf.deinit(allocator);

        const writer = buf.writer(allocator);

        if (self.is_regression) {
            try writer.print("❌ {s}: {d:.2}% SLOWER (regression)\n", .{ self.name, self.change_percent });
        } else if (self.change_percent < -5.0) {
            try writer.print("✅ {s}: {d:.2}% faster (improvement)\n", .{ self.name, -self.change_percent });
        } else {
            try writer.print("⚪ {s}: {d:.2}% change (stable)\n", .{ self.name, self.change_percent });
        }

        try writer.print("   Current: {d:.2} ns, Baseline: {d:.2} ns\n", .{ self.current_mean, self.baseline_mean });

        return buf.toOwnedSlice(allocator);
    }
};

pub const Comparator = struct {
    allocator: Allocator,
    regression_threshold: f64,

    pub fn init(allocator: Allocator, regression_threshold: f64) Comparator {
        return .{
            .allocator = allocator,
            .regression_threshold = regression_threshold,
        };
    }

    pub fn loadBaseline(self: Comparator, path: []const u8) !std.StringHashMap(f64) {
        var baseline_map = std.StringHashMap(f64).init(self.allocator);
        errdefer baseline_map.deinit();

        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024); // 1MB max
        defer self.allocator.free(content);

        // Parse JSON to extract benchmark means
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, content, .{});
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return error.InvalidBaseline;

        const benchmarks = root.object.get("benchmarks") orelse return error.NoBenchmarks;
        if (benchmarks != .array) return error.InvalidBenchmarks;

        for (benchmarks.array.items) |item| {
            if (item != .object) continue;

            const name_val = item.object.get("name") orelse continue;
            const mean_val = item.object.get("mean_ns") orelse continue;

            if (name_val != .string) continue;
            if (mean_val != .float and mean_val != .integer) continue;

            const name = try self.allocator.dupe(u8, name_val.string);
            const mean = if (mean_val == .float) mean_val.float else @as(f64, @floatFromInt(mean_val.integer));

            try baseline_map.put(name, mean);
        }

        return baseline_map;
    }

    pub fn compare(self: Comparator, current: []const BenchmarkResult, baseline_path: []const u8) ![]ComparisonResult {
        var baseline_map = try self.loadBaseline(baseline_path);
        defer {
            var it = baseline_map.keyIterator();
            while (it.next()) |key| {
                self.allocator.free(key.*);
            }
            baseline_map.deinit();
        }

        var results = std.ArrayList(ComparisonResult){};
        defer results.deinit(self.allocator);

        for (current) |bench_result| {
            if (baseline_map.get(bench_result.name)) |baseline_mean| {
                const change_percent = ((bench_result.mean - baseline_mean) / baseline_mean) * 100.0;
                const is_regression = change_percent > self.regression_threshold;

                try results.append(self.allocator, ComparisonResult{
                    .name = bench_result.name,
                    .current_mean = bench_result.mean,
                    .baseline_mean = baseline_mean,
                    .change_percent = change_percent,
                    .is_regression = is_regression,
                    .regression_threshold = self.regression_threshold,
                });
            }
        }

        return results.toOwnedSlice(self.allocator);
    }

    pub fn printComparison(self: Comparator, file: std.fs.File, comparisons: []const ComparisonResult) !void {
        _ = self;

        var buf: [512]u8 = undefined;

        const header = try std.fmt.bufPrint(&buf, "\n{s}{s}Baseline Comparison{s}\n", .{ bench.Formatter.BOLD, bench.Formatter.CYAN, bench.Formatter.RESET });
        try file.writeAll(header);

        const divider = try std.fmt.bufPrint(&buf, "{s}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{s}\n", .{ bench.Formatter.DIM, bench.Formatter.RESET });
        try file.writeAll(divider);

        var has_regression = false;
        for (comparisons) |comp| {
            if (comp.is_regression) has_regression = true;

            const status = if (comp.is_regression)
                "❌"
            else if (comp.change_percent < -5.0)
                "✅"
            else
                "⚪";

            const color = if (comp.is_regression)
                bench.Formatter.YELLOW
            else if (comp.change_percent < -5.0)
                bench.Formatter.GREEN
            else
                bench.Formatter.DIM;

            const line = try std.fmt.bufPrint(&buf, "  {s} {s}{s}{s}: {s}{d:.2}%{s}\n", .{
                status,
                bench.Formatter.BOLD,
                comp.name,
                bench.Formatter.RESET,
                color,
                comp.change_percent,
                bench.Formatter.RESET,
            });
            try file.writeAll(line);

            const detail = try std.fmt.bufPrint(&buf, "     {s}Current: {d:.2} ns | Baseline: {d:.2} ns{s}\n", .{
                bench.Formatter.DIM,
                comp.current_mean,
                comp.baseline_mean,
                bench.Formatter.RESET,
            });
            try file.writeAll(detail);
        }

        try file.writeAll("\n");

        if (has_regression) {
            const warning = try std.fmt.bufPrint(&buf, "{s}⚠️  Performance regressions detected!{s}\n\n", .{ bench.Formatter.YELLOW, bench.Formatter.RESET });
            try file.writeAll(warning);
        }
    }
};
