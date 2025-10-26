//! Flamegraph Support - Generate profiling data for flamegraph visualization
//!
//! Features:
//! - Generate folded stack format compatible with flamegraph.pl
//! - Platform-specific profiler recommendations
//! - Instructions for system profilers (perf, Instruments, Tracy)
//! - Simple call tree visualization

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Generator for flamegraph-compatible output and profiling instructions
pub const FlamegraphGenerator = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) FlamegraphGenerator {
        return .{ .allocator = allocator };
    }

    /// Generate instructions for creating a flamegraph from benchmark results
    /// This provides the command-line instructions to use with external profiling tools
    pub fn generateInstructions(self: FlamegraphGenerator, writer: std.fs.File, executable_name: []const u8) !void {
        _ = self;

        try writer.writeAll("\n");
        try writer.writeAll("=== Flamegraph Generation Instructions ===\n\n");
        try writer.writeAll("To generate a flamegraph, you'll need to use system profiling tools:\n\n");

        // macOS instructions
        try writer.writeAll("On macOS (using Instruments):\n");
        try writer.writeAll("  1. Run: xcrun xctrace record --template 'Time Profiler' --launch -- ./");
        try writer.writeAll(executable_name);
        try writer.writeAll("\n");
        try writer.writeAll("  2. Open the resulting .trace file in Instruments\n");
        try writer.writeAll("  3. Export call tree data\n\n");

        // Linux instructions
        try writer.writeAll("On Linux (using perf):\n");
        try writer.writeAll("  1. Run: perf record -F 99 -g ./");
        try writer.writeAll(executable_name);
        try writer.writeAll("\n");
        try writer.writeAll("  2. Generate flamegraph data: perf script > out.perf\n");
        try writer.writeAll("  3. Convert to flamegraph format:\n");
        try writer.writeAll("     git clone https://github.com/brendangregg/FlameGraph\n");
        try writer.writeAll("     ./FlameGraph/stackcollapse-perf.pl out.perf > out.folded\n");
        try writer.writeAll("     ./FlameGraph/flamegraph.pl out.folded > flamegraph.svg\n\n");

        // Alternative using tracy
        try writer.writeAll("Using Tracy Profiler (cross-platform):\n");
        try writer.writeAll("  1. Integrate Tracy into your Zig code\n");
        try writer.writeAll("  2. Run the Tracy server\n");
        try writer.writeAll("  3. Run your benchmark executable\n");
        try writer.writeAll("  4. Capture and export the trace\n\n");

        try writer.writeAll("Note: Flamegraph generation requires external tools and system-level profiling.\n");
        try writer.writeAll("This framework focuses on statistical benchmarking rather than sampling profiling.\n");
    }

    /// Generate a simple text-based call tree representation
    /// This is a simplified alternative to flamegraphs that doesn't require external tools
    pub fn generateCallTree(self: FlamegraphGenerator, writer: std.fs.File, benchmark_name: []const u8, execution_time_ns: u64) !void {
        _ = self;

        try writer.writeAll("\n");
        try writer.writeAll("=== Call Tree (Simplified) ===\n\n");

        var buf: [256]u8 = undefined;
        const header = try std.fmt.bufPrint(&buf, "{s}\n", .{benchmark_name});
        try writer.writeAll(header);

        const time = try std.fmt.bufPrint(&buf, "├─ Total Time: {d} ns ({d:.2} µs)\n", .{
            execution_time_ns,
            @as(f64, @floatFromInt(execution_time_ns)) / 1000.0,
        });
        try writer.writeAll(time);

        try writer.writeAll("└─ Execution completed\n\n");

        try writer.writeAll("For detailed call stack profiling, use system profilers:\n");
        try writer.writeAll("  - macOS: Instruments (Time Profiler)\n");
        try writer.writeAll("  - Linux: perf, valgrind --tool=callgrind\n");
        try writer.writeAll("  - Cross-platform: Tracy Profiler, samply\n");
    }

    /// Generate flamegraph-compatible folded stack format from benchmark results
    /// This creates a simple representation that can be fed to flamegraph.pl
    pub fn generateFoldedStacks(self: FlamegraphGenerator, file_path: []const u8, benchmark_name: []const u8, execution_count: usize) !void {
        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();

        var buf: [512]u8 = undefined;

        // Generate a simplified folded stack format
        // Format: func1;func2;func3 count
        const line = try std.fmt.bufPrint(&buf, "main;{s};benchmark_execution {d}\n", .{
            benchmark_name,
            execution_count,
        });
        try file.writeAll(line);

        // Write completion message
        const stdout = std.fs.File.stdout();
        const msg = try std.fmt.bufPrint(&buf, "✓ Folded stacks written to: {s}\n", .{file_path});
        try stdout.writeAll(msg);
        try stdout.writeAll("  To generate flamegraph: flamegraph.pl ");
        try stdout.writeAll(file_path);
        try stdout.writeAll(" > flamegraph.svg\n");

        _ = self;
    }
};

/// Integration helper for profiling tools
pub const ProfilerIntegration = struct {
    pub fn detectAvailableProfilers(allocator: Allocator) ![]const []const u8 {
        var profilers = std.ArrayList([]const u8){};

        // Check for perf (Linux)
        if (std.process.hasEnvVarConstant("PATH")) {
            const result = std.process.Child.run(.{
                .allocator = allocator,
                .argv = &[_][]const u8{ "which", "perf" },
            }) catch null;

            if (result) |r| {
                defer allocator.free(r.stdout);
                defer allocator.free(r.stderr);
                if (r.term.Exited == 0) {
                    try profilers.append(allocator, "perf");
                }
            }
        }

        // Check for Instruments (macOS)
        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "which", "xcrun" },
        }) catch null;

        if (result) |r| {
            defer allocator.free(r.stdout);
            defer allocator.free(r.stderr);
            if (r.term.Exited == 0) {
                try profilers.append(allocator, "instruments");
            }
        }

        return profilers.toOwnedSlice(allocator);
    }

    pub fn recommendProfiler() []const u8 {
        return switch (@import("builtin").os.tag) {
            .macos => "Instruments (xcrun xctrace)",
            .linux => "perf",
            .windows => "Windows Performance Toolkit",
            else => "Tracy Profiler",
        };
    }
};
