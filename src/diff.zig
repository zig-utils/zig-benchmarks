//! Benchmark Result Diff Viewer
//!
//! Features:
//! - Compare two benchmark result sets
//! - Visual diff output with color coding
//! - Highlight regressions and improvements
//! - Side-by-side comparison
//! - Summary statistics of changes

const std = @import("std");
const bench = @import("bench");
const Allocator = std.mem.Allocator;

/// Difference type
pub const DiffType = enum {
    improved,    // Performance got better (faster)
    regressed,   // Performance got worse (slower)
    unchanged,   // No significant change
    added,       // New benchmark
    removed,     // Benchmark removed
};

/// Benchmark comparison result
pub const BenchmarkDiff = struct {
    name: []const u8,
    diff_type: DiffType,
    old_mean_ns: ?f64,
    new_mean_ns: ?f64,
    percent_change: f64,
    old_ops_per_sec: ?f64,
    new_ops_per_sec: ?f64,
};

/// Full diff result
pub const DiffResult = struct {
    diffs: []BenchmarkDiff,
    total_benchmarks: usize,
    improved_count: usize,
    regressed_count: usize,
    unchanged_count: usize,
    added_count: usize,
    removed_count: usize,
    allocator: Allocator,

    pub fn deinit(self: *DiffResult) void {
        self.allocator.free(self.diffs);
    }
};

/// Diff viewer configuration
pub const DiffConfig = struct {
    /// Threshold for considering a change significant (percentage)
    significance_threshold: f64 = 5.0,

    /// Show only regressions
    regressions_only: bool = false,

    /// Show only improvements
    improvements_only: bool = false,

    /// Sort by magnitude of change
    sort_by_change: bool = true,
};

/// Benchmark diff viewer
pub const DiffViewer = struct {
    config: DiffConfig,
    allocator: Allocator,

    pub fn init(allocator: Allocator, config: DiffConfig) DiffViewer {
        return .{
            .config = config,
            .allocator = allocator,
        };
    }

    /// Compare two JSON result files
    pub fn compareFiles(self: *DiffViewer, old_path: []const u8, new_path: []const u8) !DiffResult {
        // Read old results
        const old_file = try std.fs.cwd().openFile(old_path, .{});
        defer old_file.close();
        const old_content = try old_file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(old_content);

        // Read new results
        const new_file = try std.fs.cwd().openFile(new_path, .{});
        defer new_file.close();
        const new_content = try new_file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(new_content);

        // Parse JSON (simplified - in real implementation use std.json)
        // For now, return a mock result
        var diffs = std.ArrayList(BenchmarkDiff).init(self.allocator);

        // This is a placeholder - actual implementation would parse JSON
        _ = old_content;
        _ = new_content;

        return DiffResult{
            .diffs = try diffs.toOwnedSlice(),
            .total_benchmarks = 0,
            .improved_count = 0,
            .regressed_count = 0,
            .unchanged_count = 0,
            .added_count = 0,
            .removed_count = 0,
            .allocator = self.allocator,
        };
    }

    /// Compare two result maps
    pub fn compare(
        self: *DiffViewer,
        old_results: std.StringHashMap(f64),
        new_results: std.StringHashMap(f64),
    ) !DiffResult {
        var diffs = std.ArrayList(BenchmarkDiff).init(self.allocator);
        var improved: usize = 0;
        var regressed: usize = 0;
        var unchanged: usize = 0;
        var added: usize = 0;
        var removed: usize = 0;

        // Check all new benchmarks
        var new_it = new_results.iterator();
        while (new_it.next()) |entry| {
            const name = entry.key_ptr.*;
            const new_mean = entry.value_ptr.*;

            if (old_results.get(name)) |old_mean| {
                const percent_change = ((new_mean - old_mean) / old_mean) * 100.0;
                const abs_change = @abs(percent_change);

                const diff_type: DiffType = if (abs_change < self.config.significance_threshold)
                    .unchanged
                else if (new_mean < old_mean)
                    .improved
                else
                    .regressed;

                switch (diff_type) {
                    .improved => improved += 1,
                    .regressed => regressed += 1,
                    .unchanged => unchanged += 1,
                    else => {},
                }

                try diffs.append(.{
                    .name = name,
                    .diff_type = diff_type,
                    .old_mean_ns = old_mean,
                    .new_mean_ns = new_mean,
                    .percent_change = percent_change,
                    .old_ops_per_sec = 1_000_000_000.0 / old_mean,
                    .new_ops_per_sec = 1_000_000_000.0 / new_mean,
                });
            } else {
                // New benchmark added
                added += 1;
                try diffs.append(.{
                    .name = name,
                    .diff_type = .added,
                    .old_mean_ns = null,
                    .new_mean_ns = new_mean,
                    .percent_change = 0.0,
                    .old_ops_per_sec = null,
                    .new_ops_per_sec = 1_000_000_000.0 / new_mean,
                });
            }
        }

        // Check for removed benchmarks
        var old_it = old_results.iterator();
        while (old_it.next()) |entry| {
            const name = entry.key_ptr.*;
            const old_mean = entry.value_ptr.*;

            if (!new_results.contains(name)) {
                removed += 1;
                try diffs.append(.{
                    .name = name,
                    .diff_type = .removed,
                    .old_mean_ns = old_mean,
                    .new_mean_ns = null,
                    .percent_change = 0.0,
                    .old_ops_per_sec = 1_000_000_000.0 / old_mean,
                    .new_ops_per_sec = null,
                });
            }
        }

        // Sort by magnitude of change if requested
        if (self.config.sort_by_change) {
            const items = diffs.items;
            std.mem.sort(BenchmarkDiff, items, {}, struct {
                fn lessThan(_: void, a: BenchmarkDiff, b: BenchmarkDiff) bool {
                    return @abs(a.percent_change) > @abs(b.percent_change);
                }
            }.lessThan);
        }

        return DiffResult{
            .diffs = try diffs.toOwnedSlice(),
            .total_benchmarks = new_results.count(),
            .improved_count = improved,
            .regressed_count = regressed,
            .unchanged_count = unchanged,
            .added_count = added,
            .removed_count = removed,
            .allocator = self.allocator,
        };
    }

    /// Print diff results
    pub fn printDiff(result: *const DiffResult) !void {
        const stdout = std.fs.File.stdout();
        var buf: [512]u8 = undefined;

        const header = try std.fmt.bufPrint(&buf, "\n{s}=== Benchmark Diff Report ==={s}\n\n", .{
            bench.Formatter.BOLD,
            bench.Formatter.RESET,
        });
        try stdout.writeAll(header);

        // Summary
        const summary = try std.fmt.bufPrint(&buf, "{s}Summary:{s}\n", .{
            bench.Formatter.BOLD,
            bench.Formatter.RESET,
        });
        try stdout.writeAll(summary);

        const improved_line = try std.fmt.bufPrint(&buf, "  {s}✓ Improved:{s} {d}\n", .{
            bench.Formatter.GREEN,
            bench.Formatter.RESET,
            result.improved_count,
        });
        try stdout.writeAll(improved_line);

        const regressed_line = try std.fmt.bufPrint(&buf, "  {s}✗ Regressed:{s} {d}\n", .{
            bench.Formatter.RED,
            bench.Formatter.RESET,
            result.regressed_count,
        });
        try stdout.writeAll(regressed_line);

        const unchanged_line = try std.fmt.bufPrint(&buf, "  {s}• Unchanged:{s} {d}\n", .{
            bench.Formatter.DIM,
            bench.Formatter.RESET,
            result.unchanged_count,
        });
        try stdout.writeAll(unchanged_line);

        if (result.added_count > 0) {
            const added_line = try std.fmt.bufPrint(&buf, "  {s}+ Added:{s} {d}\n", .{
                bench.Formatter.CYAN,
                bench.Formatter.RESET,
                result.added_count,
            });
            try stdout.writeAll(added_line);
        }

        if (result.removed_count > 0) {
            const removed_line = try std.fmt.bufPrint(&buf, "  {s}- Removed:{s} {d}\n", .{
                bench.Formatter.YELLOW,
                bench.Formatter.RESET,
                result.removed_count,
            });
            try stdout.writeAll(removed_line);
        }

        // Details
        try stdout.writeAll("\n");
        const details_header = try std.fmt.bufPrint(&buf, "{s}Details:{s}\n", .{
            bench.Formatter.BOLD,
            bench.Formatter.RESET,
        });
        try stdout.writeAll(details_header);

        for (result.diffs) |diff| {
            try printBenchmarkDiff(&diff);
        }
    }

    fn printBenchmarkDiff(diff: *const BenchmarkDiff) !void {
        const stdout = std.fs.File.stdout();
        var buf: [512]u8 = undefined;

        const symbol = switch (diff.diff_type) {
            .improved => "✓",
            .regressed => "✗",
            .unchanged => "•",
            .added => "+",
            .removed => "-",
        };

        const color = switch (diff.diff_type) {
            .improved => bench.Formatter.GREEN,
            .regressed => bench.Formatter.RED,
            .unchanged => bench.Formatter.DIM,
            .added => bench.Formatter.CYAN,
            .removed => bench.Formatter.YELLOW,
        };

        const name_line = try std.fmt.bufPrint(&buf, "\n  {s}{s} {s}{s}\n", .{
            color,
            symbol,
            diff.name,
            bench.Formatter.RESET,
        });
        try stdout.writeAll(name_line);

        if (diff.old_mean_ns) |old_mean| {
            if (diff.new_mean_ns) |new_mean| {
                const old_line = try std.fmt.bufPrint(&buf, "    Old: {d:.2} ns  ({d:.2} ops/sec)\n", .{
                    old_mean,
                    diff.old_ops_per_sec orelse 0.0,
                });
                try stdout.writeAll(old_line);

                const new_line = try std.fmt.bufPrint(&buf, "    New: {d:.2} ns  ({d:.2} ops/sec)\n", .{
                    new_mean,
                    diff.new_ops_per_sec orelse 0.0,
                });
                try stdout.writeAll(new_line);

                const change_line = try std.fmt.bufPrint(&buf, "    Change: {s}{d:.2}%{s}\n", .{
                    if (diff.percent_change < 0) bench.Formatter.GREEN else bench.Formatter.RED,
                    diff.percent_change,
                    bench.Formatter.RESET,
                });
                try stdout.writeAll(change_line);
            }
        } else if (diff.new_mean_ns) |new_mean| {
            const new_line = try std.fmt.bufPrint(&buf, "    New: {d:.2} ns  ({d:.2} ops/sec)\n", .{
                new_mean,
                diff.new_ops_per_sec orelse 0.0,
            });
            try stdout.writeAll(new_line);
        }
    }
};
