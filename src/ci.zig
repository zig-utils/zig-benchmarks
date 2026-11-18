//! CI/CD Integration - Helpers for continuous integration environments
//!
//! Features:
//! - Auto-detection of CI environments (GitHub Actions, GitLab CI, etc.)
//! - Platform-specific output formatting
//! - Regression checking with build failure support
//! - Summary generation for CI logs

const std = @import("std");
const bench = @import("bench");
const comparison = @import("comparison");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const BenchmarkResult = bench.BenchmarkResult;

/// Configuration for CI/CD integration
pub const CIConfig = struct {
    fail_on_regression: bool = true,
    regression_threshold: f64 = 10.0, // 10% slower
    baseline_path: ?[]const u8 = null,
    output_format: OutputFormat = .github_actions,
};

pub const OutputFormat = enum {
    github_actions,
    gitlab_ci,
    generic,
};

pub const CIHelper = struct {
    allocator: Allocator,
    io: Io,
    config: CIConfig,

    pub fn init(allocator: Allocator, io: Io, config: CIConfig) CIHelper {
        return .{
            .allocator = allocator,
            .io = io,
            .config = config,
        };
    }

    pub fn checkRegressions(self: *CIHelper, results: []const BenchmarkResult) !bool {
        if (self.config.baseline_path == null) {
            std.debug.print("No baseline specified, skipping regression check\n", .{});
            return false;
        }

        const comparator = comparison.Comparator.init(self.allocator, self.io, self.config.regression_threshold);
        const comparisons = try comparator.compare(results, self.config.baseline_path.?);
        defer self.allocator.free(comparisons);

        var has_regression = false;
        for (comparisons) |comp| {
            if (comp.is_regression) {
                has_regression = true;
                try self.reportRegression(comp);
            }
        }

        return has_regression;
    }

    fn reportRegression(self: *CIHelper, comp: comparison.ComparisonResult) !void {
        var stdout_buf: [512]u8 = undefined;
        var stdout_writer = Io.File.stdout().writerStreaming(self.io, &stdout_buf);
        const stdout = &stdout_writer.interface;
        var buf: [512]u8 = undefined;

        switch (self.config.output_format) {
            .github_actions => {
                const msg = try std.fmt.bufPrint(&buf, "::error title=Performance Regression::{s} is {d:.2}% slower than baseline (threshold: {d:.2}%)\n", .{
                    comp.name,
                    comp.change_percent,
                    self.config.regression_threshold,
                });
                try stdout.writeAll(msg);
            },
            .gitlab_ci => {
                const msg = try std.fmt.bufPrint(&buf, "❌ REGRESSION: {s} is {d:.2}% slower than baseline\n", .{
                    comp.name,
                    comp.change_percent,
                });
                try stdout.writeAll(msg);
            },
            .generic => {
                const msg = try std.fmt.bufPrint(&buf, "[REGRESSION] {s}: {d:.2}% slower (baseline: {d:.2} ns, current: {d:.2} ns)\n", .{
                    comp.name,
                    comp.change_percent,
                    comp.baseline_mean,
                    comp.current_mean,
                });
                try stdout.writeAll(msg);
            },
        }
        try stdout.flush();
    }

    pub fn generateSummary(self: *CIHelper, results: []const BenchmarkResult) !void {
        var stdout_buf: [1024]u8 = undefined;
        var stdout_writer = Io.File.stdout().writerStreaming(self.io, &stdout_buf);
        const stdout = &stdout_writer.interface;
        var buf: [1024]u8 = undefined;

        switch (self.config.output_format) {
            .github_actions => {
                try stdout.writeAll("::group::Benchmark Results\n");

                for (results) |result| {
                    const line = try std.fmt.bufPrint(&buf, "{s}: {d:.2} µs ({d:.2} ops/sec)\n", .{
                        result.name,
                        result.mean / 1000.0,
                        result.ops_per_sec,
                    });
                    try stdout.writeAll(line);
                }

                try stdout.writeAll("::endgroup::\n");

                // Create summary
                const summary_start = try std.fmt.bufPrint(&buf, "::notice title=Benchmark Summary::Ran {d} benchmarks\n", .{results.len});
                try stdout.writeAll(summary_start);
            },
            .gitlab_ci => {
                try stdout.writeAll("\n=== Benchmark Results ===\n");
                for (results) |result| {
                    const line = try std.fmt.bufPrint(&buf, "✓ {s}: {d:.2} µs\n", .{
                        result.name,
                        result.mean / 1000.0,
                    });
                    try stdout.writeAll(line);
                }
            },
            .generic => {
                try stdout.writeAll("\n--- Benchmark Summary ---\n");
                for (results) |result| {
                    const line = try std.fmt.bufPrint(&buf, "{s}: mean={d:.2}ns stddev={d:.2}ns ops/sec={d:.2}\n", .{
                        result.name,
                        result.mean,
                        result.stddev,
                        result.ops_per_sec,
                    });
                    try stdout.writeAll(line);
                }
            },
        }
        try stdout.flush();
    }

    pub fn shouldFailBuild(self: *CIHelper, has_regression: bool) bool {
        return self.config.fail_on_regression and has_regression;
    }
};

/// Detect the CI environment from the process environment
/// (`std.process.Init.environ_map` in a 0.17 `main`).
pub fn detectCIEnvironment(environ_map: *const std.process.Environ.Map) OutputFormat {
    if (environ_map.contains("GITHUB_ACTIONS")) return .github_actions;
    if (environ_map.contains("GITLAB_CI")) return .gitlab_ci;
    return .generic;
}
