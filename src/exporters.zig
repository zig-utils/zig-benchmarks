//! Custom Result Exporters (XML, Markdown, HTML, etc.)
//!
//! Features:
//! - XML export for integration with other tools
//! - Markdown export for documentation
//! - HTML export with charts
//! - YAML export for configuration
//! - Custom format support via templates

const std = @import("std");
const bench = @import("bench");
const Allocator = std.mem.Allocator;

/// Export format
pub const ExportFormat = enum {
    xml,
    markdown,
    html,
    yaml,
    custom,
};

/// XML exporter
pub const XMLExporter = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) XMLExporter {
        return .{ .allocator = allocator };
    }

    /// Export benchmark results to XML
    pub fn exportResults(self: *XMLExporter, results: []const bench.BenchmarkResult, output_path: []const u8) !void {
        _ = self;
        const file = try std.fs.cwd().createFile(output_path, .{});
        defer file.close();

        try file.writeAll("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
        try file.writeAll("<benchmarks>\n");

        for (results) |result| {
            try file.writeAll("  <benchmark>\n");
            try writeXMLField(file, "name", result.name, 4);
            try writeXMLNumericField(file, "iterations", result.iterations, 4);
            try writeXMLNumericField(file, "mean_ns", result.mean, 4);
            try writeXMLNumericField(file, "stddev_ns", result.stddev, 4);
            try writeXMLNumericField(file, "min_ns", result.min, 4);
            try writeXMLNumericField(file, "max_ns", result.max, 4);
            try writeXMLNumericField(file, "p50_ns", result.p50, 4);
            try writeXMLNumericField(file, "p75_ns", result.p75, 4);
            try writeXMLNumericField(file, "p99_ns", result.p99, 4);
            try writeXMLNumericField(file, "ops_per_sec", result.ops_per_sec, 4);
            try file.writeAll("  </benchmark>\n");
        }

        try file.writeAll("</benchmarks>\n");
    }

    fn writeXMLField(file: std.fs.File, name: []const u8, value: []const u8, indent: usize) !void {
        var spaces_buf: [128]u8 = undefined;
        const spaces = spaces_buf[0..indent];
        @memset(spaces, ' ');

        var buf: [512]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "{s}<{s}>{s}</{s}>\n", .{ spaces, name, value, name });
        try file.writeAll(line);
    }

    fn writeXMLNumericField(file: std.fs.File, name: []const u8, value: anytype, indent: usize) !void {
        var spaces_buf: [128]u8 = undefined;
        const spaces = spaces_buf[0..indent];
        @memset(spaces, ' ');

        var buf: [512]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "{s}<{s}>{d}</{s}>\n", .{ spaces, name, value, name });
        try file.writeAll(line);
    }
};

/// Markdown exporter
pub const MarkdownExporter = struct {
    allocator: Allocator,
    include_charts: bool,

    pub fn init(allocator: Allocator, include_charts: bool) MarkdownExporter {
        return .{
            .allocator = allocator,
            .include_charts = include_charts,
        };
    }

    /// Export benchmark results to Markdown
    pub fn exportResults(self: *MarkdownExporter, results: []const bench.BenchmarkResult, output_path: []const u8) !void {
        const file = try std.fs.cwd().createFile(output_path, .{});
        defer file.close();

        try file.writeAll("# Benchmark Results\n\n");
        try file.writeAll("## Summary\n\n");

        // Table header
        try file.writeAll("| Benchmark | Mean | Std Dev | Min | Max | P99 | Ops/sec |\n");
        try file.writeAll("|-----------|------|---------|-----|-----|-----|--------|\n");

        // Table rows
        for (results) |result| {
            var buf: [1024]u8 = undefined;
            const row = try std.fmt.bufPrint(&buf, "| {s} | {d:.2} ns | {d:.2} ns | {d:.2} ns | {d:.2} ns | {d:.2} ns | {d:.2} |\n", .{
                result.name,
                result.mean,
                result.stddev,
                @as(f64, @floatFromInt(result.min)),
                @as(f64, @floatFromInt(result.max)),
                @as(f64, @floatFromInt(result.p99)),
                result.ops_per_sec,
            });
            try file.writeAll(row);
        }

        try file.writeAll("\n## Details\n\n");

        for (results) |result| {
            try self.writeDetailedResult(file, &result);
        }

        if (self.include_charts) {
            try file.writeAll("\n## Performance Chart\n\n");
            try file.writeAll("```mermaid\n");
            try file.writeAll("graph LR\n");
            for (results, 0..) |result, i| {
                var buf: [256]u8 = undefined;
                const node = try std.fmt.bufPrint(&buf, "  {s}[{s}: {d:.2} ns]\n", .{
                    try self.sanitizeName(result.name),
                    result.name,
                    result.mean,
                });
                try file.writeAll(node);
                _ = i;
            }
            try file.writeAll("```\n");
        }
    }

    fn writeDetailedResult(self: *MarkdownExporter, file: std.fs.File, result: *const bench.BenchmarkResult) !void {
        _ = self;
        var buf: [1024]u8 = undefined;

        const header = try std.fmt.bufPrint(&buf, "### {s}\n\n", .{result.name});
        try file.writeAll(header);

        const iterations = try std.fmt.bufPrint(&buf, "- **Iterations:** {d}\n", .{result.iterations});
        try file.writeAll(iterations);

        const mean = try std.fmt.bufPrint(&buf, "- **Mean:** {d:.2} ns\n", .{result.mean});
        try file.writeAll(mean);

        const stddev = try std.fmt.bufPrint(&buf, "- **Std Dev:** {d:.2} ns\n", .{result.stddev});
        try file.writeAll(stddev);

        const percentiles = try std.fmt.bufPrint(&buf, "- **Percentiles:** P50={d} ns, P75={d} ns, P99={d} ns\n", .{
            result.p50,
            result.p75,
            result.p99,
        });
        try file.writeAll(percentiles);

        const ops = try std.fmt.bufPrint(&buf, "- **Ops/sec:** {d:.2}\n\n", .{result.ops_per_sec});
        try file.writeAll(ops);
    }

    fn sanitizeName(self: *MarkdownExporter, name: []const u8) ![]const u8 {
        _ = self;
        var buf: [128]u8 = undefined;
        var i: usize = 0;
        for (name) |c| {
            if (std.ascii.isAlphanumeric(c) or c == '_') {
                buf[i] = c;
                i += 1;
            } else {
                buf[i] = '_';
                i += 1;
            }
        }
        return buf[0..i];
    }
};

/// HTML exporter with interactive charts
pub const HTMLExporter = struct {
    allocator: Allocator,
    title: []const u8,
    include_chart_js: bool,

    pub fn init(allocator: Allocator, title: []const u8, include_chart_js: bool) HTMLExporter {
        return .{
            .allocator = allocator,
            .title = title,
            .include_chart_js = include_chart_js,
        };
    }

    /// Export benchmark results to HTML
    pub fn exportResults(self: *HTMLExporter, results: []const bench.BenchmarkResult, output_path: []const u8) !void {
        const file = try std.fs.cwd().createFile(output_path, .{});
        defer file.close();

        try self.writeHeader(file);
        try self.writeTable(file, results);
        if (self.include_chart_js) {
            try self.writeChart(file, results);
        }
        try self.writeFooter(file);
    }

    fn writeHeader(self: *HTMLExporter, file: std.fs.File) !void {
        var buf: [1024]u8 = undefined;
        const header = try std.fmt.bufPrint(&buf,
            \\<!DOCTYPE html>
            \\<html lang="en">
            \\<head>
            \\    <meta charset="UTF-8">
            \\    <meta name="viewport" content="width=device-width, initial-scale=1.0">
            \\    <title>{s}</title>
            \\    <style>
            \\        body {{ font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }}
            \\        h1 {{ color: #333; }}
            \\        table {{ width: 100%; border-collapse: collapse; background: white; }}
            \\        th, td {{ padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }}
            \\        th {{ background-color: #4CAF50; color: white; }}
            \\        tr:hover {{ background-color: #f5f5f5; }}
            \\        .chart-container {{ margin: 20px 0; background: white; padding: 20px; }}
            \\    </style>
        , .{self.title});
        try file.writeAll(header);

        if (self.include_chart_js) {
            try file.writeAll("    <script src=\"https://cdn.jsdelivr.net/npm/chart.js\"></script>\n");
        }

        try file.writeAll("</head>\n<body>\n");

        const title_line = try std.fmt.bufPrint(&buf, "    <h1>{s}</h1>\n", .{self.title});
        try file.writeAll(title_line);
    }

    fn writeTable(self: *HTMLExporter, file: std.fs.File, results: []const bench.BenchmarkResult) !void {
        _ = self;
        try file.writeAll("    <table>\n");
        try file.writeAll("        <tr>\n");
        try file.writeAll("            <th>Benchmark</th>\n");
        try file.writeAll("            <th>Mean (ns)</th>\n");
        try file.writeAll("            <th>Std Dev</th>\n");
        try file.writeAll("            <th>Min</th>\n");
        try file.writeAll("            <th>Max</th>\n");
        try file.writeAll("            <th>P99</th>\n");
        try file.writeAll("            <th>Ops/sec</th>\n");
        try file.writeAll("        </tr>\n");

        for (results) |result| {
            var buf: [1024]u8 = undefined;
            const row = try std.fmt.bufPrint(&buf,
                \\        <tr>
                \\            <td>{s}</td>
                \\            <td>{d:.2}</td>
                \\            <td>{d:.2}</td>
                \\            <td>{d}</td>
                \\            <td>{d}</td>
                \\            <td>{d}</td>
                \\            <td>{d:.2}</td>
                \\        </tr>
                \\
            , .{
                result.name,
                result.mean,
                result.stddev,
                result.min,
                result.max,
                result.p99,
                result.ops_per_sec,
            });
            try file.writeAll(row);
        }

        try file.writeAll("    </table>\n");
    }

    fn writeChart(self: *HTMLExporter, file: std.fs.File, results: []const bench.BenchmarkResult) !void {
        _ = self;
        try file.writeAll("    <div class=\"chart-container\">\n");
        try file.writeAll("        <canvas id=\"benchmarkChart\"></canvas>\n");
        try file.writeAll("    </div>\n");
        try file.writeAll("    <script>\n");
        try file.writeAll("        const ctx = document.getElementById('benchmarkChart');\n");
        try file.writeAll("        new Chart(ctx, {\n");
        try file.writeAll("            type: 'bar',\n");
        try file.writeAll("            data: {\n");
        try file.writeAll("                labels: [");

        for (results, 0..) |result, i| {
            var buf: [256]u8 = undefined;
            const label = if (i < results.len - 1)
                try std.fmt.bufPrint(&buf, "'{s}', ", .{result.name})
            else
                try std.fmt.bufPrint(&buf, "'{s}'", .{result.name});
            try file.writeAll(label);
        }

        try file.writeAll("],\n");
        try file.writeAll("                datasets: [{\n");
        try file.writeAll("                    label: 'Mean Time (ns)',\n");
        try file.writeAll("                    data: [");

        for (results, 0..) |result, i| {
            var buf: [128]u8 = undefined;
            const value = if (i < results.len - 1)
                try std.fmt.bufPrint(&buf, "{d:.2}, ", .{result.mean})
            else
                try std.fmt.bufPrint(&buf, "{d:.2}", .{result.mean});
            try file.writeAll(value);
        }

        try file.writeAll("],\n");
        try file.writeAll("                    backgroundColor: 'rgba(75, 192, 192, 0.2)',\n");
        try file.writeAll("                    borderColor: 'rgba(75, 192, 192, 1)',\n");
        try file.writeAll("                    borderWidth: 1\n");
        try file.writeAll("                }]\n");
        try file.writeAll("            },\n");
        try file.writeAll("            options: {\n");
        try file.writeAll("                responsive: true,\n");
        try file.writeAll("                scales: { y: { beginAtZero: true } }\n");
        try file.writeAll("            }\n");
        try file.writeAll("        });\n");
        try file.writeAll("    </script>\n");
    }

    fn writeFooter(self: *HTMLExporter, file: std.fs.File) !void {
        _ = self;
        try file.writeAll("</body>\n</html>\n");
    }
};

/// YAML exporter
pub const YAMLExporter = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) YAMLExporter {
        return .{ .allocator = allocator };
    }

    /// Export benchmark results to YAML
    pub fn exportResults(self: *YAMLExporter, results: []const bench.BenchmarkResult, output_path: []const u8) !void {
        _ = self;
        const file = try std.fs.cwd().createFile(output_path, .{});
        defer file.close();

        try file.writeAll("benchmarks:\n");

        for (results) |result| {
            var buf: [1024]u8 = undefined;

            const name_line = try std.fmt.bufPrint(&buf, "  - name: \"{s}\"\n", .{result.name});
            try file.writeAll(name_line);

            const iterations_line = try std.fmt.bufPrint(&buf, "    iterations: {d}\n", .{result.iterations});
            try file.writeAll(iterations_line);

            const mean_line = try std.fmt.bufPrint(&buf, "    mean_ns: {d:.2}\n", .{result.mean});
            try file.writeAll(mean_line);

            const stddev_line = try std.fmt.bufPrint(&buf, "    stddev_ns: {d:.2}\n", .{result.stddev});
            try file.writeAll(stddev_line);

            const min_line = try std.fmt.bufPrint(&buf, "    min_ns: {d}\n", .{result.min});
            try file.writeAll(min_line);

            const max_line = try std.fmt.bufPrint(&buf, "    max_ns: {d}\n", .{result.max});
            try file.writeAll(max_line);

            const p50_line = try std.fmt.bufPrint(&buf, "    p50_ns: {d}\n", .{result.p50});
            try file.writeAll(p50_line);

            const p75_line = try std.fmt.bufPrint(&buf, "    p75_ns: {d}\n", .{result.p75});
            try file.writeAll(p75_line);

            const p99_line = try std.fmt.bufPrint(&buf, "    p99_ns: {d}\n", .{result.p99});
            try file.writeAll(p99_line);

            const ops_line = try std.fmt.bufPrint(&buf, "    ops_per_sec: {d:.2}\n", .{result.ops_per_sec});
            try file.writeAll(ops_line);
        }
    }
};
