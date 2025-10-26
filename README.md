# Zig Bench

A modern, performant, and beautiful benchmark framework for Zig, inspired by [mitata](https://github.com/evanwashere/mitata).

## Features

- **High Precision Timing** - Uses Zig's built-in high-resolution timer for accurate measurements
- **Statistical Analysis** - Calculates mean, standard deviation, min/max, and percentiles (P50, P75, P99)
- **Beautiful CLI Output** - Colorized output with clear formatting
- **Flexible Configuration** - Customize warmup iterations, min/max iterations, and minimum time
- **Async Support** - Built-in support for benchmarking async/error-handling functions
- **Zero Dependencies** - Uses only Zig's standard library
- **Automatic Iteration Adjustment** - Intelligently adjusts iterations based on operation speed
- **Comparative Analysis** - Automatically identifies and highlights the fastest benchmark

## Installation

### Using Zig Package Manager

Add to your `build.zig.zon`:

```zig
.{
    .name = "my-project",
    .version = "0.1.0",
    .dependencies = .{
        .bench = .{
            .url = "https://github.com/yourusername/zig-bench/archive/main.tar.gz",
            .hash = "...",
        },
    },
}
```

Then in your `build.zig`:

```zig
const bench = b.dependency("bench", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("bench", bench.module("bench"));
```

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

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var suite = bench.BenchmarkSuite.init(allocator);
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

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var suite = bench.BenchmarkSuite.init(allocator);
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

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var suite = bench.BenchmarkSuite.init(allocator);
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
const async_bench = bench.async_bench;

var result: []u8 = undefined;

fn asyncOperation() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buffer = try allocator.alloc(u8, 1024);
    defer allocator.free(buffer);

    @memset(buffer, 'A');
    result = buffer;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var suite = async_bench.AsyncBenchmarkSuite.init(allocator);
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
    pub fn init(allocator: Allocator) BenchmarkSuite
    pub fn deinit(self: *BenchmarkSuite) void
    pub fn add(self: *BenchmarkSuite, name: []const u8, func: *const fn () void) !void
    pub fn addWithOptions(self: *BenchmarkSuite, name: []const u8, func: *const fn () void, opts: BenchmarkOptions) !void
    pub fn run(self: *BenchmarkSuite) !void
};
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
    pub fn init(allocator: Allocator) AsyncBenchmarkSuite
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

Run examples:

```bash
# Build and run all examples
zig build examples

# Run specific example
zig build run-basic
zig build run-async
zig build run-custom_options
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

- Uses Zig's `std.time.Timer` for high-resolution timing
- Minimal overhead - the framework itself adds negligible time
- No heap allocations in the hot benchmark loop
- Efficient statistical calculations
- Automatic iteration adjustment based on operation speed

## Building from Source

```bash
# Clone the repository
git clone https://github.com/yourusername/zig-bench.git
cd zig-bench

# Run tests
zig build test

# Build examples
zig build examples

# Run specific example
zig build run-basic
```

## Requirements

- Zig 0.13.0 or later

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see LICENSE file for details

## Acknowledgments

Inspired by [mitata](https://github.com/evanwashere/mitata), a beautiful JavaScript benchmarking library.

## Roadmap

- [ ] JSON/CSV export for results
- [ ] Historical comparison (compare against saved baselines)
- [ ] Memory profiling integration
- [ ] Flamegraph generation support
- [ ] CI/CD integration helpers
- [ ] Regression detection
- [ ] Custom allocator benchmarking
- [ ] Benchmark filtering (run specific benchmarks by pattern)

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
