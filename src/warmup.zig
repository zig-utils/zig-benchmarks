//! Automatic Warmup Detection - Intelligently determine optimal warmup
//!
//! Features:
//! - Detect when performance stabilizes
//! - Use coefficient of variation to measure stability
//! - Adaptive warmup based on operation characteristics
//! - Avoid over-warming or under-warming

const std = @import("std");
const bench = @import("bench");

/// Configuration for automatic warmup detection
pub const WarmupConfig = struct {
    /// Maximum warmup iterations to try (default: 50)
    max_warmup_iterations: u32 = 50,

    /// Minimum warmup iterations (default: 3)
    min_warmup_iterations: u32 = 3,

    /// Window size for stability check (default: 5)
    stability_window: u32 = 5,

    /// Coefficient of variation threshold for stability (default: 0.05 = 5%)
    cv_threshold: f64 = 0.05,
};

/// Result of warmup detection
pub const WarmupResult = struct {
    /// Number of iterations determined to be optimal
    optimal_iterations: u32,

    /// Whether warmup stabilized
    stabilized: bool,

    /// Coefficient of variation at stabilization
    final_cv: f64,
};

/// Automatic warmup detector
pub const WarmupDetector = struct {
    config: WarmupConfig,

    pub fn init(config: WarmupConfig) WarmupDetector {
        return .{ .config = config };
    }

    pub fn initDefault() WarmupDetector {
        return .{ .config = .{} };
    }

    /// Detect optimal warmup iterations for a function
    pub fn detect(self: *const WarmupDetector, func: *const fn () void, allocator: std.mem.Allocator) !WarmupResult {
        var samples = std.ArrayList(u64){};
        defer samples.deinit(allocator);

        var timer = try std.time.Timer.start();

        // Run initial min_warmup_iterations
        var i: u32 = 0;
        while (i < self.config.min_warmup_iterations) : (i += 1) {
            timer.reset();
            func();
            const elapsed = timer.read();
            try samples.append(allocator, elapsed);
        }

        // Continue until stability or max iterations
        while (i < self.config.max_warmup_iterations) : (i += 1) {
            timer.reset();
            func();
            const elapsed = timer.read();
            try samples.append(allocator, elapsed);

            // Check stability once we have enough samples
            if (samples.items.len >= self.config.stability_window) {
                const is_stable = try self.checkStability(samples.items, allocator);
                if (is_stable) {
                    const cv = try self.calculateCV(samples.items);
                    return WarmupResult{
                        .optimal_iterations = i + 1,
                        .stabilized = true,
                        .final_cv = cv,
                    };
                }
            }
        }

        // Reached max iterations without stabilizing
        const cv = try self.calculateCV(samples.items);
        return WarmupResult{
            .optimal_iterations = self.config.max_warmup_iterations,
            .stabilized = false,
            .final_cv = cv,
        };
    }

    /// Check if the recent samples show stability
    fn checkStability(self: *const WarmupDetector, samples: []const u64, _: std.mem.Allocator) !bool {
        if (samples.len < self.config.stability_window) return false;

        // Get the last stability_window samples
        const window_start = samples.len - self.config.stability_window;
        const window = samples[window_start..];

        const cv = try self.calculateCVForWindow(window);
        return cv <= self.config.cv_threshold;
    }

    /// Calculate coefficient of variation for a window
    fn calculateCVForWindow(self: *const WarmupDetector, window: []const u64) !f64 {
        _ = self;
        if (window.len == 0) return 0.0;

        const mean_val = bench.Stats.mean(window);
        if (mean_val == 0.0) return 0.0;

        const stddev_val = bench.Stats.stddev(window, mean_val);
        return stddev_val / mean_val;
    }

    /// Calculate coefficient of variation for all samples
    fn calculateCV(self: *const WarmupDetector, samples: []const u64) !f64 {
        return self.calculateCVForWindow(samples);
    }
};

/// Apply automatic warmup detection to benchmark options
pub fn applyAutoWarmup(
    func: *const fn () void,
    base_opts: bench.BenchmarkOptions,
    allocator: std.mem.Allocator,
) !bench.BenchmarkOptions {
    const detector = WarmupDetector.initDefault();
    const result = try detector.detect(func, allocator);

    var opts = base_opts;
    opts.warmup_iterations = result.optimal_iterations;
    return opts;
}

/// Warmup with allocator function
pub fn detectWithAllocator(
    detector: *const WarmupDetector,
    func: *const fn (std.mem.Allocator) void,
    allocator: std.mem.Allocator,
) !WarmupResult {
    var samples = std.ArrayList(u64){};
    defer samples.deinit(allocator);

    var timer = try std.time.Timer.start();

    // Run initial min_warmup_iterations
    var i: u32 = 0;
    while (i < detector.config.min_warmup_iterations) : (i += 1) {
        timer.reset();
        func(allocator);
        const elapsed = timer.read();
        try samples.append(allocator, elapsed);
    }

    // Continue until stability or max iterations
    while (i < detector.config.max_warmup_iterations) : (i += 1) {
        timer.reset();
        func(allocator);
        const elapsed = timer.read();
        try samples.append(allocator, elapsed);

        if (samples.items.len >= detector.config.stability_window) {
            const is_stable = try detector.checkStability(samples.items, allocator);
            if (is_stable) {
                const cv = try detector.calculateCV(samples.items);
                return WarmupResult{
                    .optimal_iterations = i + 1,
                    .stabilized = true,
                    .final_cv = cv,
                };
            }
        }
    }

    const cv = try detector.calculateCV(samples.items);
    return WarmupResult{
        .optimal_iterations = detector.config.max_warmup_iterations,
        .stabilized = false,
        .final_cv = cv,
    };
}
