//! Comprehensive example demonstrating all Phase 3 advanced features:
//! - A/B testing framework
//! - Benchmark diff viewer
//! - Custom result exporters (XML, Markdown, HTML, YAML)
//! - Monitoring integration (Prometheus)
//! - Profiling mode with traces

const std = @import("std");
const bench = @import("bench");
const ab_testing = @import("ab_testing");
const diff = @import("diff");
const exporters = @import("exporters");
const monitoring = @import("monitoring");
const profiling = @import("profiling");

// Implementation A - using a simple loop
fn implementationA() void {
    var sum: u64 = 0;
    var i: u64 = 0;
    while (i < 1000) : (i += 1) {
        sum +%= i;
    }
    std.mem.doNotOptimizeAway(&sum);
}

// Implementation B - using a different approach
fn implementationB() void {
    var sum: u64 = 0;
    var i: u64 = 0;
    while (i < 1000) : (i += 1) {
        sum +%= i *% 2 / 2;
    }
    std.mem.doNotOptimizeAway(&sum);
}

fn fastBenchmark() void {
    var sum: u64 = 0;
    var i: u64 = 0;
    while (i < 100) : (i += 1) {
        sum +%= i;
    }
    std.mem.doNotOptimizeAway(&sum);
}

fn slowBenchmark() void {
    var sum: u64 = 0;
    var i: u64 = 0;
    while (i < 10000) : (i += 1) {
        sum +%= i *% i;
    }
    std.mem.doNotOptimizeAway(&sum);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.fs.File.stdout();
    var buf: [512]u8 = undefined;

    const header = try std.fmt.bufPrint(&buf, "\n{s}=== Phase 3 Advanced Features Demo ==={s}\n\n", .{
        bench.Formatter.BOLD,
        bench.Formatter.RESET,
    });
    try stdout.writeAll(header);

    // 1. A/B Testing
    const section1 = try std.fmt.bufPrint(&buf, "{s}[1] A/B Testing Framework{s}\n", .{
        bench.Formatter.CYAN,
        bench.Formatter.RESET,
    });
    try stdout.writeAll(section1);

    const ab_config = ab_testing.ABTestConfig{
        .iterations = 500,
        .warmup_iterations = 5,
        .confidence_level = 0.95,
        .min_effect_size = 5.0,
        .randomize_order = true,
    };

    const ab_test = ab_testing.ABTest.init(
        allocator,
        "Implementation Comparison",
        implementationA,
        implementationB,
        ab_config,
    );

    const ab_result = try ab_test.run();
    try ab_testing.ABTest.printResults(&ab_result);

    // 2. Benchmark Diff Viewer
    const section2 = try std.fmt.bufPrint(&buf, "\n{s}[2] Benchmark Diff Viewer{s}\n", .{
        bench.Formatter.CYAN,
        bench.Formatter.RESET,
    });
    try stdout.writeAll(section2);

    // Create old and new results for comparison
    var old_results = std.StringHashMap(f64).init(allocator);
    defer old_results.deinit();
    try old_results.put("Fast Benchmark", 150.0);
    try old_results.put("Slow Benchmark", 15000.0);
    try old_results.put("Removed Benchmark", 5000.0);

    var new_results = std.StringHashMap(f64).init(allocator);
    defer new_results.deinit();
    try new_results.put("Fast Benchmark", 140.0); // 6.7% improvement
    try new_results.put("Slow Benchmark", 16000.0); // 6.7% regression
    try new_results.put("New Benchmark", 2000.0);

    const diff_config = diff.DiffConfig{
        .significance_threshold = 5.0,
        .regressions_only = false,
        .improvements_only = false,
        .sort_by_change = true,
    };

    var diff_viewer = diff.DiffViewer.init(allocator, diff_config);
    var diff_result = try diff_viewer.compare(old_results, new_results);
    defer diff_result.deinit();

    try diff.DiffViewer.printDiff(&diff_result);

    // 3. Custom Exporters
    const section3 = try std.fmt.bufPrint(&buf, "\n{s}[3] Custom Result Exporters{s}\n", .{
        bench.Formatter.CYAN,
        bench.Formatter.RESET,
    });
    try stdout.writeAll(section3);

    // Run some benchmarks to get real results
    var suite = bench.BenchmarkSuite.init(allocator);
    defer suite.deinit();

    try suite.add("Fast Benchmark", fastBenchmark);
    try suite.add("Slow Benchmark", slowBenchmark);

    try suite.run();

    // Get results for export (simplified - in real implementation would get from suite)
    const samples1 = std.ArrayList(u64){};
    const samples2 = std.ArrayList(u64){};

    const benchmark_results = [_]bench.BenchmarkResult{
        .{
            .name = "Fast Benchmark",
            .samples = samples1,
            .allocator = allocator,
            .mean = 140.5,
            .stddev = 15.2,
            .min = 120,
            .max = 200,
            .p50 = 138,
            .p75 = 145,
            .p99 = 180,
            .ops_per_sec = 7117438.0,
            .iterations = 1000,
        },
        .{
            .name = "Slow Benchmark",
            .samples = samples2,
            .allocator = allocator,
            .mean = 16100.0,
            .stddev = 1200.0,
            .min = 14000,
            .max = 20000,
            .p50 = 16000,
            .p75 = 16500,
            .p99 = 19000,
            .ops_per_sec = 62111.8,
            .iterations = 1000,
        },
    };

    // XML Export
    var xml_exporter = exporters.XMLExporter.init(allocator);
    try xml_exporter.exportResults(&benchmark_results, "benchmark_results.xml");
    const xml_line = try std.fmt.bufPrint(&buf, "  {s}✓{s} Exported to XML: benchmark_results.xml\n", .{
        bench.Formatter.GREEN,
        bench.Formatter.RESET,
    });
    try stdout.writeAll(xml_line);

    // Markdown Export
    var md_exporter = exporters.MarkdownExporter.init(allocator, false);
    try md_exporter.exportResults(&benchmark_results, "benchmark_results.md");
    const md_line = try std.fmt.bufPrint(&buf, "  {s}✓{s} Exported to Markdown: benchmark_results.md\n", .{
        bench.Formatter.GREEN,
        bench.Formatter.RESET,
    });
    try stdout.writeAll(md_line);

    // HTML Export
    var html_exporter = exporters.HTMLExporter.init(allocator, "Benchmark Results", true);
    try html_exporter.exportResults(&benchmark_results, "benchmark_results.html");
    const html_line = try std.fmt.bufPrint(&buf, "  {s}✓{s} Exported to HTML: benchmark_results.html\n", .{
        bench.Formatter.GREEN,
        bench.Formatter.RESET,
    });
    try stdout.writeAll(html_line);

    // YAML Export
    var yaml_exporter = exporters.YAMLExporter.init(allocator);
    try yaml_exporter.exportResults(&benchmark_results, "benchmark_results.yaml");
    const yaml_line = try std.fmt.bufPrint(&buf, "  {s}✓{s} Exported to YAML: benchmark_results.yaml\n", .{
        bench.Formatter.GREEN,
        bench.Formatter.RESET,
    });
    try stdout.writeAll(yaml_line);

    // 4. Prometheus Monitoring Integration
    const section4 = try std.fmt.bufPrint(&buf, "\n{s}[4] Prometheus Monitoring Integration{s}\n", .{
        bench.Formatter.CYAN,
        bench.Formatter.RESET,
    });
    try stdout.writeAll(section4);

    var prom_exporter = monitoring.PrometheusExporter.init(allocator, "benchmark");
    defer prom_exporter.deinit();

    try prom_exporter.addLabel("environment", "test");
    try prom_exporter.addLabel("version", "1.0.0");
    try prom_exporter.exportResults(&benchmark_results, "benchmark_metrics.prom");

    const prom_line = try std.fmt.bufPrint(&buf, "  {s}✓{s} Exported Prometheus metrics: benchmark_metrics.prom\n", .{
        bench.Formatter.GREEN,
        bench.Formatter.RESET,
    });
    try stdout.writeAll(prom_line);

    // Generate Grafana dashboard
    var dashboard = try monitoring.GrafanaDashboard.createDefaultDashboard(allocator, "benchmark");
    defer dashboard.deinit();

    try dashboard.generateJSON("grafana_dashboard.json");
    const grafana_line = try std.fmt.bufPrint(&buf, "  {s}✓{s} Generated Grafana dashboard: grafana_dashboard.json\n", .{
        bench.Formatter.GREEN,
        bench.Formatter.RESET,
    });
    try stdout.writeAll(grafana_line);

    // 5. Profiling Mode
    const section5 = try std.fmt.bufPrint(&buf, "\n{s}[5] Profiling Mode with Traces{s}\n", .{
        bench.Formatter.CYAN,
        bench.Formatter.RESET,
    });
    try stdout.writeAll(section5);

    const prof_bench = profiling.ProfilingBenchmark.init(
        allocator,
        "Fast Benchmark",
        fastBenchmark,
        100,
    );

    var prof_result = try prof_bench.run();
    defer prof_result.deinit();

    try prof_result.printSummary();

    try prof_result.exportTrace("benchmark_trace.json");
    const trace_line = try std.fmt.bufPrint(&buf, "  {s}✓{s} Exported Chrome trace: benchmark_trace.json\n", .{
        bench.Formatter.GREEN,
        bench.Formatter.RESET,
    });
    try stdout.writeAll(trace_line);

    const footer = try std.fmt.bufPrint(&buf, "\n{s}=== Demo Complete ==={s}\n", .{
        bench.Formatter.BOLD,
        bench.Formatter.RESET,
    });
    try stdout.writeAll(footer);

    const summary_header = try std.fmt.bufPrint(&buf, "\n{s}Generated Files:{s}\n", .{
        bench.Formatter.BOLD,
        bench.Formatter.RESET,
    });
    try stdout.writeAll(summary_header);

    const files = [_][]const u8{
        "  - benchmark_results.xml",
        "  - benchmark_results.md",
        "  - benchmark_results.html",
        "  - benchmark_results.yaml",
        "  - benchmark_metrics.prom",
        "  - grafana_dashboard.json",
        "  - benchmark_trace.json",
    };

    for (files) |file| {
        try stdout.writeAll(file);
        try stdout.writeAll("\n");
    }
}
