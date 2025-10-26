//! Statistical Outlier Detection and Removal
//!
//! Features:
//! - Multiple outlier detection methods (IQR, Z-score, MAD)
//! - Configurable sensitivity
//! - Preserve sample integrity while removing anomalies
//! - Detailed outlier reporting

const std = @import("std");
const bench = @import("bench");
const Allocator = std.mem.Allocator;

/// Method for detecting outliers
pub const OutlierMethod = enum {
    /// Interquartile Range (IQR) method - robust to extreme outliers
    iqr,
    /// Z-score method - assumes normal distribution
    zscore,
    /// Median Absolute Deviation (MAD) - very robust
    mad,
};

/// Configuration for outlier detection
pub const OutlierConfig = struct {
    method: OutlierMethod = .iqr,

    /// Multiplier for IQR method (default: 1.5)
    /// Lower = more aggressive, Higher = more conservative
    iqr_multiplier: f64 = 1.5,

    /// Threshold for Z-score method (default: 3.0)
    /// Typically 2.0-3.0 for normal distributions
    zscore_threshold: f64 = 3.0,

    /// Multiplier for MAD method (default: 3.0)
    mad_multiplier: f64 = 3.0,
};

/// Result of outlier detection
pub const OutlierResult = struct {
    /// Cleaned samples with outliers removed
    cleaned_samples: []u64,

    /// Outliers that were removed
    outliers: []u64,

    /// Number of outliers detected
    outlier_count: usize,

    /// Percentage of samples that were outliers
    outlier_percentage: f64,

    allocator: Allocator,

    pub fn deinit(self: *OutlierResult) void {
        self.allocator.free(self.cleaned_samples);
        self.allocator.free(self.outliers);
    }
};

/// Outlier detector
pub const OutlierDetector = struct {
    config: OutlierConfig,

    pub fn init(config: OutlierConfig) OutlierDetector {
        return .{ .config = config };
    }

    pub fn initDefault() OutlierDetector {
        return .{ .config = .{} };
    }

    /// Detect and remove outliers from samples
    pub fn detectAndRemove(self: *const OutlierDetector, samples: []const u64, allocator: Allocator) !OutlierResult {
        if (samples.len < 4) {
            // Not enough samples to detect outliers reliably
            const cleaned = try allocator.dupe(u64, samples);
            const outliers = try allocator.alloc(u64, 0);
            return OutlierResult{
                .cleaned_samples = cleaned,
                .outliers = outliers,
                .outlier_count = 0,
                .outlier_percentage = 0.0,
                .allocator = allocator,
            };
        }

        return switch (self.config.method) {
            .iqr => try self.detectIQR(samples, allocator),
            .zscore => try self.detectZScore(samples, allocator),
            .mad => try self.detectMAD(samples, allocator),
        };
    }

    /// IQR (Interquartile Range) method
    fn detectIQR(self: *const OutlierDetector, samples: []const u64, allocator: Allocator) !OutlierResult {
        // Sort samples to calculate quartiles
        var sorted = try allocator.dupe(u64, samples);
        defer allocator.free(sorted);
        std.mem.sort(u64, sorted, {}, std.sort.asc(u64));

        const q1 = bench.Stats.percentile(sorted, 0.25);
        const q3 = bench.Stats.percentile(sorted, 0.75);
        const iqr = @as(f64, @floatFromInt(q3 - q1));

        const lower_bound = @as(f64, @floatFromInt(q1)) - (self.config.iqr_multiplier * iqr);
        const upper_bound = @as(f64, @floatFromInt(q3)) + (self.config.iqr_multiplier * iqr);

        return try self.filterOutliers(samples, lower_bound, upper_bound, allocator);
    }

    /// Z-score method
    fn detectZScore(self: *const OutlierDetector, samples: []const u64, allocator: Allocator) !OutlierResult {
        const mean_val = bench.Stats.mean(samples);
        const stddev_val = bench.Stats.stddev(samples, mean_val);

        if (stddev_val == 0.0) {
            // All values are the same, no outliers
            const cleaned = try allocator.dupe(u64, samples);
            const outliers = try allocator.alloc(u64, 0);
            return OutlierResult{
                .cleaned_samples = cleaned,
                .outliers = outliers,
                .outlier_count = 0,
                .outlier_percentage = 0.0,
                .allocator = allocator,
            };
        }

        const lower_bound = mean_val - (self.config.zscore_threshold * stddev_val);
        const upper_bound = mean_val + (self.config.zscore_threshold * stddev_val);

        return try self.filterOutliers(samples, lower_bound, upper_bound, allocator);
    }

    /// MAD (Median Absolute Deviation) method
    fn detectMAD(self: *const OutlierDetector, samples: []const u64, allocator: Allocator) !OutlierResult {
        var sorted = try allocator.dupe(u64, samples);
        defer allocator.free(sorted);

        const median = bench.Stats.percentile(sorted, 0.50);
        const median_f = @as(f64, @floatFromInt(median));

        // Calculate absolute deviations from median
        var deviations = try allocator.alloc(u64, samples.len);
        defer allocator.free(deviations);

        for (samples, 0..) |sample, i| {
            const sample_f = @as(f64, @floatFromInt(sample));
            const abs_dev = @abs(sample_f - median_f);
            deviations[i] = @intFromFloat(abs_dev);
        }

        // Calculate MAD
        std.mem.sort(u64, deviations, {}, std.sort.asc(u64));
        const mad = bench.Stats.percentile(deviations, 0.50);
        const mad_f = @as(f64, @floatFromInt(mad));

        // Scale factor to make MAD consistent with standard deviation
        const scale = 1.4826;
        const threshold = scale * mad_f * self.config.mad_multiplier;

        const lower_bound = median_f - threshold;
        const upper_bound = median_f + threshold;

        return try self.filterOutliers(samples, lower_bound, upper_bound, allocator);
    }

    /// Filter samples based on bounds
    fn filterOutliers(self: *const OutlierDetector, samples: []const u64, lower: f64, upper: f64, allocator: Allocator) !OutlierResult {
        _ = self;

        var cleaned_list = std.ArrayList(u64){};
        var outlier_list = std.ArrayList(u64){};
        defer cleaned_list.deinit(allocator);
        defer outlier_list.deinit(allocator);

        for (samples) |sample| {
            const sample_f = @as(f64, @floatFromInt(sample));
            if (sample_f >= lower and sample_f <= upper) {
                try cleaned_list.append(allocator, sample);
            } else {
                try outlier_list.append(allocator, sample);
            }
        }

        const outlier_count = outlier_list.items.len;
        const outlier_pct = (@as(f64, @floatFromInt(outlier_count)) / @as(f64, @floatFromInt(samples.len))) * 100.0;

        return OutlierResult{
            .cleaned_samples = try cleaned_list.toOwnedSlice(allocator),
            .outliers = try outlier_list.toOwnedSlice(allocator),
            .outlier_count = outlier_count,
            .outlier_percentage = outlier_pct,
            .allocator = allocator,
        };
    }
};

/// Apply outlier removal to benchmark result
pub fn cleanBenchmarkResult(result: *bench.BenchmarkResult, config: OutlierConfig, allocator: Allocator) !OutlierResult {
    const detector = OutlierDetector.init(config);
    return try detector.detectAndRemove(result.samples.items, allocator);
}
