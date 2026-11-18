# Zig Bench

A modern, performant, and beautiful benchmark framework for Zig, inspired by [mitata](https://github.com/evanwashere/mitata).

## Features

- **High Precision Timing** - Uses the monotonic `std.Io` clock for accurate measurements
- **Statistical Analysis** - Calculates mean, standard deviation, min/max, and percentiles (P50, P75, P99)
- **Beautiful CLI Output** - Colorized output with clear formatting
- **Flexible Configuration** - Customize warmup iterations, min/max iterations, and minimum time
- **Async Support** - Built-in support for benchmarking async/error-handling functions
- **Zero Dependencies** - Uses only Zig's standard library
- **Automatic Iteration Adjustment** - Intelligently adjusts iterations based on operation speed
- **Comparative Analysis** - Automatically identifies and highlights the fastest benchmark

## Installation

Requires **Zig 0.17.0-dev.1857 or later**. Clocks, stdout and file output go
through `std.Io`, so the entry points (`BenchmarkSuite.init`, exporters, ...)
take an `io: std.Io`, which a 0.17 `main` receives from `std.process.Init`.

### Using Zig Package Manager

Add to your `build.zig.zon`:

```sh
zig fetch --save=bench https://registry.pantry.dev/zig/packages/zig-bench/0.2.1/tarball
```

Then in your `build.zig`:

```zig
const bench = b.dependency("bench", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("bench", bench.module("bench"));
```

Every feature module is exported under its file name: `bench`, `exporters`, `monitoring`,
`comparison`, `ci`, `groups`, `parallel`, `profiling` and the rest.

### Manual Installation

Clone this repository and add it as a module in your project:

```zig
const bench_module = b.addModule("bench", .{
    .root_source_file = b.path("path/to/zig-bench/src/bench.zig"),
});

exe.root_module.addImport("bench", bench_module);
```

## Quick Start

### Basic Benchmark

```zig
const std = @import("std");
const bench = @import("bench");

var global_sum: u64 = 0;

fn benchmarkLoop() void {
    var sum: u64 = 0;
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        sum += i;
    }
    global_sum = sum;
}

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;

    var suite = bench.BenchmarkSuite.init(allocator, init.io);
    defer suite.deinit();

    try suite.add("Loop 1000 times", benchmarkLoop);
    try suite.run();
}
```

### Multiple Benchmarks

```zig
const std = @import("std");
const bench = @import("bench");

var result: u64 = 0;

fn fibonacci(n: u32) u64 {
    if (n <= 1) return n;
    return fibonacci(n - 1) + fibonacci(n - 2);
}

fn benchFib20() void {
    result = fibonacci(20);
}

fn benchFib25() void {
    result = fibonacci(25);
}

fn benchFib30() void {
    result = fibonacci(30);
}

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;

    var suite = bench.BenchmarkSuite.init(allocator, init.io);
    defer suite.deinit();

    try suite.add("Fibonacci(20)", benchFib20);
    try suite.add("Fibonacci(25)", benchFib25);
    try suite.add("Fibonacci(30)", benchFib30);

    try suite.run();
}
```

### Custom Options

Customize warmup, iterations, and timing:

```zig
const std = @import("std");
const bench = @import("bench");

fn slowOperation() void {
    var sum: u64 = 0;
    var i: u32 = 0;
    while (i < 10_000_000) : (i += 1) {
        sum += i;
    }
}

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;

    var suite = bench.BenchmarkSuite.init(allocator, init.io);
    defer suite.deinit();

    try suite.addWithOptions("Slow Operation", slowOperation, .{
        .warmup_iterations = 2,      // Fewer warmup iterations
        .min_iterations = 5,          // Minimum iterations to run
        .max_iterations = 50,         // Maximum iterations
        .min_time_ns = 2_000_000_000, // Run for at least 2 seconds
    });

    try suite.run();
}
```

### Async Benchmarks

Benchmark functions that return errors:

```zig
const std = @import("std");
const bench = @import("bench");
var result: []u8 = undefined;

fn asyncOperation() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buffer = try allocator.alloc(u8, 1024);
    defer allocator.free(buffer);

    @memset(buffer, 'A');
    result = buffer;
}

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;

    var suite = bench.AsyncBenchmarkSuite.init(allocator, init.io);
    defer suite.deinit();

    try suite.add("Async Buffer Allocation", asyncOperation);
    try suite.run();
}
```

## API Reference

### BenchmarkSuite

The main interface for running multiple benchmarks.

```zig
pub const BenchmarkSuite = struct {
    pub fn init(allocator: Allocator, io: std.Io) BenchmarkSuite
    pub fn deinit(self: *BenchmarkSuite) void
    pub fn add(self: *BenchmarkSuite, name: []const u8, func: *const fn () void) !void
    pub fn addWithOptions(self: *BenchmarkSuite, name: []const u8, func: *const fn () void, opts: BenchmarkOptions) !void
    pub fn run(self: *BenchmarkSuite) !void
};
```

### Benchmark (single run)

```zig
pub const Benchmark = struct {
    pub fn init(name: []const u8, func: *const fn () void) Benchmark
    pub fn run(self: *const Benchmark, allocator: Allocator, io: std.Io) !BenchmarkResult
};

// One-off convenience wrappers
pub fn bench(io: std.Io, name: []const u8, func: *const fn () void) !void
pub fn benchWithOptions(io: std.Io, name: []const u8, func: *const fn () void, opts: BenchmarkOptions) !void
```

### Timer

`bench.Timer` (from `src/clock.zig`) replaces the removed `std.time.Timer`:

```zig
var timer = bench.Timer.start(io); // monotonic `.awake` clock
const elapsed_ns = timer.read();
const lap_ns = timer.lap(); // read and restart
timer.reset();

const now_ms = bench.clock.milliTimestamp(io); // wall clock
```

### BenchmarkOptions

Configuration options for individual benchmarks.

```zig
pub const BenchmarkOptions = struct {
    warmup_iterations: u32 = 5,           // Number of warmup runs
    min_iterations: u32 = 10,             // Minimum iterations to execute
    max_iterations: u32 = 10_000,         // Maximum iterations to execute
    min_time_ns: u64 = 1_000_000_000,     // Minimum time to run (1 second)
    baseline: ?[]const u8 = null,         // Reserved for future baseline comparison
};
```

### BenchmarkResult

Results from a benchmark run containing statistical data.

```zig
pub const BenchmarkResult = struct {
    name: []const u8,
    samples: std.ArrayList(u64),
    mean: f64,           // Mean execution time in nanoseconds
    stddev: f64,         // Standard deviation
    min: u64,            // Minimum time
    max: u64,            // Maximum time
    p50: u64,            // 50th percentile (median)
    p75: u64,            // 75th percentile
    p99: u64,            // 99th percentile
    ops_per_sec: f64,    // Operations per second
    iterations: u64,     // Total iterations executed
};
```

### AsyncBenchmarkSuite

For benchmarking functions that can return errors.

```zig
pub const AsyncBenchmarkSuite = struct {
    pub fn init(allocator: Allocator, io: std.Io) AsyncBenchmarkSuite
    pub fn deinit(self: *AsyncBenchmarkSuite) void
    pub fn add(self: *AsyncBenchmarkSuite, name: []const u8, func: *const fn () anyerror!void) !void
    pub fn addWithOptions(self: *AsyncBenchmarkSuite, name: []const u8, func: *const fn () anyerror!void, opts: BenchmarkOptions) !void
    pub fn run(self: *AsyncBenchmarkSuite) !void
};
```

## Examples

The `examples/` directory contains several complete examples:

- `basic.zig` - Simple benchmarks comparing different operations
- `async.zig` - Async/error-handling benchmark examples
- `custom_options.zig` - Customizing benchmark parameters
- `filtering_baseline.zig` - Benchmark filtering and baseline saving
- `allocators.zig` - Comparing different allocator performance
- `advanced_features.zig` - Complete demonstration of all Phase 1 advanced features
- `phase2_features.zig` - Complete demonstration of all Phase 2 advanced features (groups, warmup, outliers, parameterized, parallel)

Run examples:

```bash
# Build and run all examples
zig build examples

# Run specific example
zig build run-basic
zig build run-async
zig build run-custom_options
zig build run-filtering_baseline
zig build run-allocators
zig build run-advanced_features
zig build run-phase2_features
```

## Output Format

Zig Bench provides beautiful, colorized output:

```
Zig Benchmark Suite
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

▶ Running: Fibonacci(20)
  Iterations: 1000
  Mean:       127.45 µs
  Std Dev:    12.34 µs
  Min:        115.20 µs
  Max:        156.78 µs
  P50:        125.90 µs
  P75:        132.45 µs
  P99:        145.67 µs
  Ops/sec:    7.85k

Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✓ Fibonacci(20) - fastest
  • Fibonacci(25) - 5.47x slower
  • Fibonacci(30) - 37.21x slower
```

## Best Practices

1. **Avoid I/O Operations**: Benchmark pure computation when possible
2. **Use Global Variables**: Store results in global variables to prevent compiler optimization
3. **Appropriate Iterations**: Fast operations need more iterations, slow operations need fewer
4. **Warmup Phase**: Always include warmup iterations for JIT/cache warming
5. **Isolate Benchmarks**: Each benchmark should test one specific operation
6. **Minimize Allocations**: Be mindful of memory allocations in the hot path

## Performance Considerations

- Uses the monotonic `std.Io` clock (`bench.Timer`) for high-resolution timing
- Minimal overhead - the framework itself adds negligible time
- No heap allocations in the hot benchmark loop
- Efficient statistical calculations
- Automatic iteration adjustment based on operation speed

## Building from Source

```bash
# Clone the repository
git clone https://github.com/yourusername/zig-bench.git
cd zig-bench

# Run all tests (unit + integration)
zig build test

# Run only unit tests
zig build test-unit

# Run only integration tests
zig build test-integration

# Build all examples
zig build examples

# Run specific example
zig build run-basic
```

## Requirements

- Zig 0.17.0-dev.1857 or later

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Community

For help, discussion about best practices, or any other conversation that would benefit from being searchable:

[Discussions on GitHub](https://github.com/zig-utils/zig-benchmarks/discussions)

For casual chit-chat with others using this package:

[Join the zig-utils Discord Server](https://discord.gg/f7wBym6JF2)

## License

MIT License - see LICENSE file for details

## Acknowledgments

Inspired by [mitata](https://github.com/evanwashere/mitata), a beautiful JavaScript benchmarking library.

## Advanced Features

Zig Bench includes a comprehensive suite of advanced features for professional benchmarking.

### Organization & Workflow

- **Benchmark Groups/Categories** - Organize related benchmarks into logical groups
- **Benchmark Filtering** - Run specific benchmarks by name pattern
- **Parameterized Benchmarks** - Test performance across different input sizes or parameters

### Performance Analysis

- **Automatic Warmup Detection** - Intelligently determine optimal warmup iterations
- **Statistical Outlier Detection** - Remove anomalies using IQR, Z-score, or MAD methods
- **Memory Profiling** - Track memory allocations, peak usage, and allocation counts
- **Multi-threaded Benchmarks** - Test parallel performance and thread scalability

### Comparison & Regression Detection

- **Historical Baseline Comparison** - Compare current results against saved baselines
- **Regression Detection** - Automatic detection of performance regressions with configurable thresholds
- **Custom Allocator Benchmarking** - Compare performance across different allocators

### Export & Visualization

- **JSON/CSV Export** - Export benchmark results to standard formats
- **Flamegraph Support** - Generate flamegraph-compatible output for profiling tools
- **Web Dashboard** - Interactive HTML dashboard for visualizing results

### CI/CD Integration

- **GitHub Actions Workflow** - Ready-to-use workflow with PR comments and artifact uploads
- **GitLab CI Template** - Complete pipeline with Pages dashboard generation
- **CI/CD Helpers** - Built-in support for GitHub Actions, GitLab CI, and generic CI systems

### Export Results to JSON/CSV

```zig
const export_mod = @import("export");

const exporter = export_mod.Exporter.init(allocator, io);

// Export to JSON
try exporter.exportToFile(results, "benchmark_results.json", .json);

// Export to CSV
try exporter.exportToFile(results, "benchmark_results.csv", .csv);
```

### Baseline Comparison & Regression Detection

```zig
const comparison_mod = @import("comparison");

// Create comparator with 10% regression threshold
const comparator = comparison_mod.Comparator.init(allocator, io, 10.0);

// Compare current results against baseline
const comparisons = try comparator.compare(results, "baseline.json");
defer allocator.free(comparisons);

// Print comparison report to any *std.Io.Writer
var stdout_buf: [4096]u8 = undefined;
var stdout_writer = std.Io.File.stdout().writerStreaming(io, &stdout_buf);
try comparator.printComparison(&stdout_writer.interface, comparisons);
try stdout_writer.interface.flush();
```

### Memory Profiling

```zig
const memory_profiler = @import("memory_profiler");

// Create profiling allocator
var profiling_allocator = memory_profiler.ProfilingAllocator.init(base_allocator);
const tracked_allocator = profiling_allocator.allocator();

// Run benchmark with tracked allocator
// ... benchmark code ...

// Get memory statistics
const stats = profiling_allocator.getStats();
// stats contains: peak_allocated, total_allocated, total_freed,
//                 current_allocated, allocation_count, free_count
```

### CI/CD Integration

```zig
const ci = @import("ci");

// Detect CI environment automatically (environ_map comes from std.process.Init)
const ci_format = ci.detectCIEnvironment(init.environ_map);

// Create CI helper with configuration
var ci_helper = ci.CIHelper.init(allocator, io, .{
    .fail_on_regression = true,
    .regression_threshold = 10.0,
    .baseline_path = "baseline.json",
    .output_format = ci_format,
});

// Generate CI-specific summary
try ci_helper.generateSummary(results);

// Check for regressions
const has_regression = try ci_helper.checkRegressions(results);
if (has_regression and ci_helper.shouldFailBuild(has_regression)) {
    std.process.exit(1); // Fail the build
}
```

### Flamegraph Generation

```zig
const flamegraph_mod = @import("flamegraph");

const flamegraph_gen = flamegraph_mod.FlamegraphGenerator.init(allocator, io);

// Generate folded stack format for flamegraph.pl
try flamegraph_gen.generateFoldedStacks("benchmark.folded", "MyBenchmark", 10000);

// Generate profiler instructions (writes to any *std.Io.Writer)
try flamegraph_gen.generateInstructions(&stdout_writer.interface, "my_executable");

// Detect available profilers
const recommended = flamegraph_mod.ProfilerIntegration.recommendProfiler();
```

### Benchmark Filtering

```zig
var suite = bench.BenchmarkSuite.init(allocator, io);
defer suite.deinit();

try suite.add("Fast Operation", fastOp);
try suite.add("Slow Operation", slowOp);
try suite.add("Fast Algorithm", fastAlgo);

// Only run benchmarks matching "Fast"
suite.setFilter("Fast");

try suite.run(); // Only runs "Fast Operation" and "Fast Algorithm"
```

### Custom Allocator Benchmarking

```zig
var suite = bench.BenchmarkSuite.init(allocator, io);
defer suite.deinit();

// Benchmark with custom allocator
try suite.addWithAllocator("GPA Benchmark", benchmarkFunc, gpa_allocator);
try suite.addWithAllocator("Arena Benchmark", benchmarkFunc, arena_allocator);

try suite.run();
```

## FAQ

### Why store results in global variables?

Modern compilers are very smart at optimizing away "dead code". If your benchmark function's result isn't used, the compiler might optimize away the entire function. Storing results in global variables prevents this.

### How are iterations determined?

The framework runs benchmarks until either:
1. The `max_iterations` limit is reached, OR
2. The `min_time_ns` has elapsed AND at least `min_iterations` have run

This ensures fast operations get enough samples while slow operations don't take too long.

### Can I benchmark allocations?

Yes! Just be aware that allocation benchmarks should:
1. Clean up allocations within the benchmark function
2. Use realistic allocation patterns
3. Consider using custom options to adjust iteration counts

### How accurate are the measurements?

Measurements use Zig's high-resolution timer which typically has nanosecond precision on modern systems. However, actual accuracy depends on:
- System load
- CPU frequency scaling
- Cache effects
- Background processes

Run multiple times and look for consistency in results.

## Phase 2 Advanced Features

### Benchmark Groups

Organize related benchmarks into categories for better organization:

```zig
const groups = @import("groups");

var manager = groups.GroupManager.init(allocator, io);
defer manager.deinit();

// Create groups
var algorithms = try manager.addGroup("Algorithms");
try algorithms.add("QuickSort", quicksortBench);
try algorithms.add("MergeSort", mergesortBench);

var io_group = try manager.addGroup("I/O Operations");
try io_group.add("File Read", fileReadBench);
try io_group.add("File Write", fileWriteBench);

// Run all groups
try manager.runAll();

// Or run specific group
try manager.runGroup("Algorithms");
```

### Automatic Warmup Detection

Let the framework automatically determine optimal warmup iterations:

```zig
const warmup = @import("warmup");

const detector = warmup.WarmupDetector.initDefault();
const result = try detector.detect(myBenchFunc, allocator, io);

std.debug.print("Optimal warmup: {d} iterations\n", .{result.optimal_iterations});
std.debug.print("Stabilized: {}\n", .{result.stabilized});
std.debug.print("CV: {d:.4}\n", .{result.final_cv});
```

### Outlier Detection and Removal

Clean benchmark data by removing statistical outliers:

```zig
const outliers = @import("outliers");

// Configure outlier detection
const config = outliers.OutlierConfig{
    .method = .iqr,  // or .zscore, .mad
    .iqr_multiplier = 1.5,
};

const detector = outliers.OutlierDetector.init(config);
var result = try detector.detectAndRemove(samples, allocator);
defer result.deinit();

std.debug.print("Removed {d} outliers ({d:.2}%)\n", .{
    result.outlier_count,
    result.outlier_percentage,
});
```

### Parameterized Benchmarks

Test performance across different input sizes:

```zig
const param = @import("parameterized");

// Define sizes to test
const sizes = [_]usize{ 10, 100, 1000, 10000 };

// Create parameterized benchmark
var suite = try param.sizeParameterized(
    allocator,
    io,
    "Array Sort",
    arraySortBench,
    &sizes,
);
defer suite.deinit();

try suite.run();
```

### Multi-threaded Benchmarks

Measure parallel performance and scalability:

```zig
const parallel = @import("parallel");

// Single parallel benchmark
const config = parallel.ParallelConfig{
    .thread_count = 4,
    .iterations_per_thread = 1000,
};

const pb = parallel.ParallelBenchmark.init(allocator, io, "Parallel Op", func, config);
var result = try pb.run();
defer result.deinit();

try parallel.ParallelBenchmark.printResult(io, &result);

// Scalability test across thread counts
const thread_counts = [_]usize{ 1, 2, 4, 8 };
const scalability = parallel.ScalabilityTest.init(
    allocator,
    io,
    "Scalability",
    func,
    &thread_counts,
    1000,
);
try scalability.run();
```

### CI/CD Integration

#### GitHub Actions

Copy `.github/workflows/benchmarks.yml` to your repository for automatic benchmarking on every push/PR:

- Runs benchmarks on multiple platforms
- Compares against baseline
- Posts results as PR comments
- Uploads artifacts

#### GitLab CI

Copy `.gitlab-ci.yml` to your repository for GitLab CI integration:

- Multi-stage pipeline (build, test, benchmark, report)
- Automatic baseline comparison
- GitLab Pages dashboard generation
- Regression detection

### Web Dashboard

Open `web/dashboard.html` in a browser to visualize benchmark results:

- Interactive charts and graphs
- Load results from JSON files or URLs
- Compare multiple benchmark runs
- Export/share visualizations

To use:
1. Run benchmarks and generate `benchmark_results.json`
2. Open `web/dashboard.html` in a browser
3. Load the JSON file or use demo data
4. Explore interactive visualizations

