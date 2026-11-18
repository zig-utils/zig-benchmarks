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
const Io = std.Io;

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
    io: Io,

    pub fn init(allocator: Allocator, io: Io) XMLExporter {
        return .{ .allocator = allocator, .io = io };
    }

    /// Export benchmark results to XML
    pub fn exportResults(self: *XMLExporter, results: []const bench.BenchmarkResult, output_path: []const u8) !void {
        const file = try Io.Dir.cwd().createFile(self.io, output_path, .{});
        defer file.close(self.io);
        var file_buf: [4096]u8 = undefined;
        var file_writer = file.writer(self.io, &file_buf);
        const w = &file_writer.interface;

        try w.writeAll("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
        try w.writeAll("<benchmarks>\n");

        for (results) |result| {
            try w.writeAll("  <benchmark>\n");
            try writeXMLField(w, "name", result.name, 4);
            try writeXMLNumericField(w, "iterations", result.iterations, 4);
            try writeXMLNumericField(w, "mean_ns", result.mean, 4);
            try writeXMLNumericField(w, "stddev_ns", result.stddev, 4);
            try writeXMLNumericField(w, "min_ns", result.min, 4);
            try writeXMLNumericField(w, "max_ns", result.max, 4);
            try writeXMLNumericField(w, "p50_ns", result.p50, 4);
            try writeXMLNumericField(w, "p75_ns", result.p75, 4);
            try writeXMLNumericField(w, "p99_ns", result.p99, 4);
            try writeXMLNumericField(w, "ops_per_sec", result.ops_per_sec, 4);
            try w.writeAll("  </benchmark>\n");
        }

        try w.writeAll("</benchmarks>\n");

        try w.flush();
    }

    fn writeXMLField(w: *Io.Writer, name: []const u8, value: []const u8, indent: usize) !void {
        var spaces_buf: [128]u8 = undefined;
        const spaces = spaces_buf[0..indent];
        @memset(spaces, ' ');

        var buf: [512]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "{s}<{s}>{s}</{s}>\n", .{ spaces, name, value, name });
        try w.writeAll(line);
    }

    fn writeXMLNumericField(w: *Io.Writer, name: []const u8, value: anytype, indent: usize) !void {
        var spaces_buf: [128]u8 = undefined;
        const spaces = spaces_buf[0..indent];
        @memset(spaces, ' ');

        var buf: [512]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "{s}<{s}>{d}</{s}>\n", .{ spaces, name, value, name });
        try w.writeAll(line);
    }
};

/// Markdown exporter
pub const MarkdownExporter = struct {
    allocator: Allocator,
    io: Io,
    include_charts: bool,

    pub fn init(allocator: Allocator, io: Io, include_charts: bool) MarkdownExporter {
        return .{
            .allocator = allocator,
            .io = io,
            .include_charts = include_charts,
        };
    }

    /// Export benchmark results to Markdown
    pub fn exportResults(self: *MarkdownExporter, results: []const bench.BenchmarkResult, output_path: []const u8) !void {
        const file = try Io.Dir.cwd().createFile(self.io, output_path, .{});
        defer file.close(self.io);
        var file_buf: [4096]u8 = undefined;
        var file_writer = file.writer(self.io, &file_buf);
        const w = &file_writer.interface;

        try w.writeAll("# Benchmark Results\n\n");
        try w.writeAll("## Summary\n\n");

        // Table header
        try w.writeAll("| Benchmark | Mean | Std Dev | Min | Max | P99 | Ops/sec |\n");
        try w.writeAll("|-----------|------|---------|-----|-----|-----|--------|\n");

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
            try w.writeAll(row);
        }

        try w.writeAll("\n## Details\n\n");

        for (results) |result| {
            try self.writeDetailedResult(w, &result);
        }

        if (self.include_charts) {
            try w.writeAll("\n## Performance Chart\n\n");
            try w.writeAll("```mermaid\n");
            try w.writeAll("graph LR\n");
            for (results, 0..) |result, i| {
                var buf: [256]u8 = undefined;
                var id_buf: [128]u8 = undefined;
                const node = try std.fmt.bufPrint(&buf, "  {s}[{s}: {d:.2} ns]\n", .{
                    sanitizeName(&id_buf, result.name),
                    result.name,
                    result.mean,
                });
                try w.writeAll(node);
                _ = i;
            }
            try w.writeAll("```\n");
        }

        try w.flush();
    }

    fn writeDetailedResult(self: *MarkdownExporter, w: *Io.Writer, result: *const bench.BenchmarkResult) !void {
        _ = self;
        var buf: [1024]u8 = undefined;

        const header = try std.fmt.bufPrint(&buf, "### {s}\n\n", .{result.name});
        try w.writeAll(header);

        const iterations = try std.fmt.bufPrint(&buf, "- **Iterations:** {d}\n", .{result.iterations});
        try w.writeAll(iterations);

        const mean = try std.fmt.bufPrint(&buf, "- **Mean:** {d:.2} ns\n", .{result.mean});
        try w.writeAll(mean);

        const stddev = try std.fmt.bufPrint(&buf, "- **Std Dev:** {d:.2} ns\n", .{result.stddev});
        try w.writeAll(stddev);

        const percentiles = try std.fmt.bufPrint(&buf, "- **Percentiles:** P50={d} ns, P75={d} ns, P99={d} ns\n", .{
            result.p50,
            result.p75,
            result.p99,
        });
        try w.writeAll(percentiles);

        const ops = try std.fmt.bufPrint(&buf, "- **Ops/sec:** {d:.2}\n\n", .{result.ops_per_sec});
        try w.writeAll(ops);
    }

    /// Mermaid node id for a benchmark name: alphanumerics and underscores, written into `out` and
    /// truncated to its length. The result borrows `out`, so the caller owns the storage.
    fn sanitizeName(out: []u8, name: []const u8) []const u8 {
        const len = @min(out.len, name.len);
        for (name[0..len], out[0..len]) |c, *dest| {
            dest.* = if (std.ascii.isAlphanumeric(c) or c == '_') c else '_';
        }
        return out[0..len];
    }
};

/// HTML exporter with interactive charts
pub const HTMLExporter = struct {
    allocator: Allocator,
    io: Io,
    title: []const u8,
    include_chart_js: bool,

    pub fn init(allocator: Allocator, io: Io, title: []const u8, include_chart_js: bool) HTMLExporter {
        return .{
            .allocator = allocator,
            .io = io,
            .title = title,
            .include_chart_js = include_chart_js,
        };
    }

    /// Export benchmark results to HTML
    pub fn exportResults(self: *HTMLExporter, results: []const bench.BenchmarkResult, output_path: []const u8) !void {
        const file = try Io.Dir.cwd().createFile(self.io, output_path, .{});
        defer file.close(self.io);
        var file_buf: [4096]u8 = undefined;
        var file_writer = file.writer(self.io, &file_buf);
        const w = &file_writer.interface;

        try self.writeHeader(w);
        try self.writeTable(w, results);
        if (self.include_chart_js) {
            try self.writeChart(w, results);
        }
        try self.writeFooter(w);

        try w.flush();
    }

    fn writeHeader(self: *HTMLExporter, w: *Io.Writer) !void {
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
        try w.writeAll(header);

        if (self.include_chart_js) {
            try w.writeAll("    <script src=\"https://cdn.jsdelivr.net/npm/chart.js\"></script>\n");
        }

        try w.writeAll("</head>\n<body>\n");

        const title_line = try std.fmt.bufPrint(&buf, "    <h1>{s}</h1>\n", .{self.title});
        try w.writeAll(title_line);
    }

    fn writeTable(self: *HTMLExporter, w: *Io.Writer, results: []const bench.BenchmarkResult) !void {
        _ = self;
        try w.writeAll("    <table>\n");
        try w.writeAll("        <tr>\n");
        try w.writeAll("            <th>Benchmark</th>\n");
        try w.writeAll("            <th>Mean (ns)</th>\n");
        try w.writeAll("            <th>Std Dev</th>\n");
        try w.writeAll("            <th>Min</th>\n");
        try w.writeAll("            <th>Max</th>\n");
        try w.writeAll("            <th>P99</th>\n");
        try w.writeAll("            <th>Ops/sec</th>\n");
        try w.writeAll("        </tr>\n");

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
            try w.writeAll(row);
        }

        try w.writeAll("    </table>\n");
    }

    fn writeChart(self: *HTMLExporter, w: *Io.Writer, results: []const bench.BenchmarkResult) !void {
        _ = self;
        try w.writeAll("    <div class=\"chart-container\">\n");
        try w.writeAll("        <canvas id=\"benchmarkChart\"></canvas>\n");
        try w.writeAll("    </div>\n");
        try w.writeAll("    <script>\n");
        try w.writeAll("        const ctx = document.getElementById('benchmarkChart');\n");
        try w.writeAll("        new Chart(ctx, {\n");
        try w.writeAll("            type: 'bar',\n");
        try w.writeAll("            data: {\n");
        try w.writeAll("                labels: [");

        for (results, 0..) |result, i| {
            var buf: [256]u8 = undefined;
            const label = if (i < results.len - 1)
                try std.fmt.bufPrint(&buf, "'{s}', ", .{result.name})
            else
                try std.fmt.bufPrint(&buf, "'{s}'", .{result.name});
            try w.writeAll(label);
        }

        try w.writeAll("],\n");
        try w.writeAll("                datasets: [{\n");
        try w.writeAll("                    label: 'Mean Time (ns)',\n");
        try w.writeAll("                    data: [");

        for (results, 0..) |result, i| {
            var buf: [128]u8 = undefined;
            const value = if (i < results.len - 1)
                try std.fmt.bufPrint(&buf, "{d:.2}, ", .{result.mean})
            else
                try std.fmt.bufPrint(&buf, "{d:.2}", .{result.mean});
            try w.writeAll(value);
        }

        try w.writeAll("],\n");
        try w.writeAll("                    backgroundColor: 'rgba(75, 192, 192, 0.2)',\n");
        try w.writeAll("                    borderColor: 'rgba(75, 192, 192, 1)',\n");
        try w.writeAll("                    borderWidth: 1\n");
        try w.writeAll("                }]\n");
        try w.writeAll("            },\n");
        try w.writeAll("            options: {\n");
        try w.writeAll("                responsive: true,\n");
        try w.writeAll("                scales: { y: { beginAtZero: true } }\n");
        try w.writeAll("            }\n");
        try w.writeAll("        });\n");
        try w.writeAll("    </script>\n");
    }

    fn writeFooter(self: *HTMLExporter, w: *Io.Writer) !void {
        _ = self;
        try w.writeAll("</body>\n</html>\n");
    }
};

/// YAML exporter
pub const YAMLExporter = struct {
    allocator: Allocator,
    io: Io,

    pub fn init(allocator: Allocator, io: Io) YAMLExporter {
        return .{ .allocator = allocator, .io = io };
    }

    /// Export benchmark results to YAML
    pub fn exportResults(self: *YAMLExporter, results: []const bench.BenchmarkResult, output_path: []const u8) !void {
        const file = try Io.Dir.cwd().createFile(self.io, output_path, .{});
        defer file.close(self.io);
        var file_buf: [4096]u8 = undefined;
        var file_writer = file.writer(self.io, &file_buf);
        const w = &file_writer.interface;

        try w.writeAll("benchmarks:\n");

        for (results) |result| {
            var buf: [1024]u8 = undefined;

            const name_line = try std.fmt.bufPrint(&buf, "  - name: \"{s}\"\n", .{result.name});
            try w.writeAll(name_line);

            const iterations_line = try std.fmt.bufPrint(&buf, "    iterations: {d}\n", .{result.iterations});
            try w.writeAll(iterations_line);

            const mean_line = try std.fmt.bufPrint(&buf, "    mean_ns: {d:.2}\n", .{result.mean});
            try w.writeAll(mean_line);

            const stddev_line = try std.fmt.bufPrint(&buf, "    stddev_ns: {d:.2}\n", .{result.stddev});
            try w.writeAll(stddev_line);

            const min_line = try std.fmt.bufPrint(&buf, "    min_ns: {d}\n", .{result.min});
            try w.writeAll(min_line);

            const max_line = try std.fmt.bufPrint(&buf, "    max_ns: {d}\n", .{result.max});
            try w.writeAll(max_line);

            const p50_line = try std.fmt.bufPrint(&buf, "    p50_ns: {d}\n", .{result.p50});
            try w.writeAll(p50_line);

            const p75_line = try std.fmt.bufPrint(&buf, "    p75_ns: {d}\n", .{result.p75});
            try w.writeAll(p75_line);

            const p99_line = try std.fmt.bufPrint(&buf, "    p99_ns: {d}\n", .{result.p99});
            try w.writeAll(p99_line);

            const ops_line = try std.fmt.bufPrint(&buf, "    ops_per_sec: {d:.2}\n", .{result.ops_per_sec});
            try w.writeAll(ops_line);
        }

        try w.flush();
    }
};

test "MarkdownExporter.sanitizeName stays inside the caller's buffer" {
    var out: [8]u8 = undefined;
    try std.testing.expectEqualStrings("a_b_c", MarkdownExporter.sanitizeName(&out, "a-b c"));
    try std.testing.expectEqualStrings("abcdefgh", MarkdownExporter.sanitizeName(&out, "abcdefghijk"));
}
