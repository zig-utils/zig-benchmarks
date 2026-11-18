//! Monitoring System Integration (Prometheus, Grafana)
//!
//! Features:
//! - Prometheus metrics exporter
//! - Grafana dashboard JSON generator
//! - Push gateway support
//! - Custom metric labels
//! - Time series data formatting

const std = @import("std");
const bench = @import("bench");
const Allocator = std.mem.Allocator;
const Io = std.Io;

/// Prometheus metric type
pub const MetricType = enum {
    gauge,
    counter,
    histogram,
    summary,
};

/// Prometheus exporter
pub const PrometheusExporter = struct {
    namespace: []const u8,
    allocator: Allocator,
    io: Io,
    labels: std.StringHashMap([]const u8),

    pub fn init(allocator: Allocator, io: Io, namespace: []const u8) PrometheusExporter {
        return .{
            .namespace = namespace,
            .allocator = allocator,
            .io = io,
            .labels = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *PrometheusExporter) void {
        self.labels.deinit();
    }

    /// Add a global label
    pub fn addLabel(self: *PrometheusExporter, key: []const u8, value: []const u8) !void {
        try self.labels.put(key, value);
    }

    /// Export benchmark results to Prometheus format
    pub fn exportResults(self: *PrometheusExporter, results: []const bench.BenchmarkResult, output_path: []const u8) !void {
        const file = try Io.Dir.cwd().createFile(self.io, output_path, .{});
        defer file.close(self.io);
        var file_buf: [4096]u8 = undefined;
        var file_writer = file.writer(self.io, &file_buf);
        const w = &file_writer.interface;

        for (results) |result| {
            try self.writeMetric(w, result);
        }

        try w.flush();
    }

    fn writeMetric(self: *PrometheusExporter, w: *Io.Writer, result: bench.BenchmarkResult) !void {
        var buf: [1024]u8 = undefined;

        // Write HELP and TYPE
        const help = try std.fmt.bufPrint(&buf, "# HELP {s}_duration_nanoseconds Benchmark execution time in nanoseconds\n", .{self.namespace});
        try w.writeAll(help);

        const type_line = try std.fmt.bufPrint(&buf, "# TYPE {s}_duration_nanoseconds histogram\n", .{self.namespace});
        try w.writeAll(type_line);

        // Write metrics with labels
        var labels_buf: [512]u8 = undefined;
        var labels_fba = std.heap.FixedBufferAllocator.init(&labels_buf);
        const labels_alloc = labels_fba.allocator();

        var labels_str = std.ArrayList(u8).empty;
        defer labels_str.deinit(labels_alloc);

        try labels_str.print(labels_alloc, "benchmark=\"{s}\"", .{result.name});

        var it = self.labels.iterator();
        while (it.next()) |entry| {
            try labels_str.print(labels_alloc, ",{s}=\"{s}\"", .{ entry.key_ptr.*, entry.value_ptr.* });
        }

        // Write mean
        const mean_metric = try std.fmt.bufPrint(&buf, "{s}_duration_nanoseconds{{{s}}} {d}\n", .{
            self.namespace,
            labels_str.items,
            result.mean,
        });
        try w.writeAll(mean_metric);

        // Write percentiles as histogram buckets
        const p50_metric = try std.fmt.bufPrint(&buf, "{s}_duration_nanoseconds_bucket{{quantile=\"0.5\",{s}}} {d}\n", .{
            self.namespace,
            labels_str.items,
            result.p50,
        });
        try w.writeAll(p50_metric);

        const p75_metric = try std.fmt.bufPrint(&buf, "{s}_duration_nanoseconds_bucket{{quantile=\"0.75\",{s}}} {d}\n", .{
            self.namespace,
            labels_str.items,
            result.p75,
        });
        try w.writeAll(p75_metric);

        const p99_metric = try std.fmt.bufPrint(&buf, "{s}_duration_nanoseconds_bucket{{quantile=\"0.99\",{s}}} {d}\n", .{
            self.namespace,
            labels_str.items,
            result.p99,
        });
        try w.writeAll(p99_metric);

        // Write ops/sec as gauge
        const ops_help = try std.fmt.bufPrint(&buf, "# HELP {s}_ops_per_second Operations per second\n", .{self.namespace});
        try w.writeAll(ops_help);

        const ops_type = try std.fmt.bufPrint(&buf, "# TYPE {s}_ops_per_second gauge\n", .{self.namespace});
        try w.writeAll(ops_type);

        const ops_metric = try std.fmt.bufPrint(&buf, "{s}_ops_per_second{{{s}}} {d:.2}\n", .{
            self.namespace,
            labels_str.items,
            result.ops_per_sec,
        });
        try w.writeAll(ops_metric);

        try w.writeAll("\n");
    }

    /// Push metrics to Prometheus Push Gateway
    pub fn pushToGateway(self: *PrometheusExporter, gateway_url: []const u8, job_name: []const u8, results: []const bench.BenchmarkResult) !void {
        _ = self;
        _ = gateway_url;
        _ = job_name;
        _ = results;
        // Implementation would use HTTP client to push to gateway
        // This is a placeholder
        return error.NotImplemented;
    }
};

/// Grafana dashboard generator
pub const GrafanaDashboard = struct {
    title: []const u8,
    allocator: Allocator,
    io: Io,
    panels: std.ArrayList(Panel),

    const Panel = struct {
        title: []const u8,
        query: []const u8,
        panel_type: []const u8,
    };

    pub fn init(allocator: Allocator, io: Io, title: []const u8) GrafanaDashboard {
        return .{
            .title = title,
            .allocator = allocator,
            .io = io,
            .panels = std.ArrayList(Panel).empty,
        };
    }

    pub fn deinit(self: *GrafanaDashboard) void {
        self.panels.deinit(self.allocator);
    }

    /// Add a panel to the dashboard
    pub fn addPanel(self: *GrafanaDashboard, title: []const u8, query: []const u8, panel_type: []const u8) !void {
        try self.panels.append(self.allocator, .{
            .title = title,
            .query = query,
            .panel_type = panel_type,
        });
    }

    /// Generate Grafana dashboard JSON
    pub fn generateJSON(self: *GrafanaDashboard, output_path: []const u8) !void {
        const file = try Io.Dir.cwd().createFile(self.io, output_path, .{});
        defer file.close(self.io);
        var file_buf: [4096]u8 = undefined;
        var file_writer = file.writer(self.io, &file_buf);
        const w = &file_writer.interface;

        var buf: [4096]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buf);
        const temp_alloc = fba.allocator();

        var json = std.ArrayList(u8).empty;
        defer json.deinit(temp_alloc);

        try json.appendSlice(temp_alloc, "{\n");
        try json.print(temp_alloc, "  \"title\": \"{s}\",\n", .{self.title});
        try json.appendSlice(temp_alloc, "  \"editable\": true,\n");
        try json.appendSlice(temp_alloc, "  \"panels\": [\n");

        for (self.panels.items, 0..) |panel, i| {
            try json.appendSlice(temp_alloc, "    {\n");
            try json.print(temp_alloc, "      \"id\": {d},\n", .{i + 1});
            try json.print(temp_alloc, "      \"title\": \"{s}\",\n", .{panel.title});
            try json.print(temp_alloc, "      \"type\": \"{s}\",\n", .{panel.panel_type});
            try json.appendSlice(temp_alloc, "      \"targets\": [\n");
            try json.appendSlice(temp_alloc, "        {\n");
            try json.print(temp_alloc, "          \"expr\": \"{s}\"\n", .{panel.query});
            try json.appendSlice(temp_alloc, "        }\n");
            try json.appendSlice(temp_alloc, "      ]\n");
            if (i < self.panels.items.len - 1) {
                try json.appendSlice(temp_alloc, "    },\n");
            } else {
                try json.appendSlice(temp_alloc, "    }\n");
            }
        }

        try json.appendSlice(temp_alloc, "  ]\n");
        try json.appendSlice(temp_alloc, "}\n");

        try w.writeAll(json.items);

        try w.flush();
    }

    /// Create a default dashboard for benchmark monitoring
    pub fn createDefaultDashboard(allocator: Allocator, io: Io, namespace: []const u8) !GrafanaDashboard {
        var dashboard = GrafanaDashboard.init(allocator, io, "Benchmark Metrics");

        // Add duration panel
        var duration_query_buf: [256]u8 = undefined;
        const duration_query = try std.fmt.bufPrint(&duration_query_buf, "{s}_duration_nanoseconds", .{namespace});
        const duration_owned = try allocator.dupe(u8, duration_query);
        try dashboard.addPanel("Execution Time (ns)", duration_owned, "graph");

        // Add ops/sec panel
        var ops_query_buf: [256]u8 = undefined;
        const ops_query = try std.fmt.bufPrint(&ops_query_buf, "{s}_ops_per_second", .{namespace});
        const ops_owned = try allocator.dupe(u8, ops_query);
        try dashboard.addPanel("Operations per Second", ops_owned, "graph");

        // Add percentiles panel
        var p99_query_buf: [256]u8 = undefined;
        const p99_query = try std.fmt.bufPrint(&p99_query_buf, "{s}_duration_nanoseconds_bucket{{quantile=\"0.99\"}}", .{namespace});
        const p99_owned = try allocator.dupe(u8, p99_query);
        try dashboard.addPanel("P99 Latency", p99_owned, "graph");

        return dashboard;
    }
};

/// Time series data point
pub const TimeSeriesPoint = struct {
    timestamp: i64,
    value: f64,
};

/// Time series collector for tracking benchmark history
pub const TimeSeriesCollector = struct {
    series: std.StringHashMap(std.ArrayList(TimeSeriesPoint)),
    allocator: Allocator,
    io: Io,

    pub fn init(allocator: Allocator, io: Io) TimeSeriesCollector {
        return .{
            .series = std.StringHashMap(std.ArrayList(TimeSeriesPoint)).init(allocator),
            .allocator = allocator,
            .io = io,
        };
    }

    pub fn deinit(self: *TimeSeriesCollector) void {
        var it = self.series.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.series.deinit();
    }

    /// Record a benchmark result
    pub fn record(self: *TimeSeriesCollector, name: []const u8, value: f64) !void {
        const timestamp = bench.clock.milliTimestamp(self.io);

        const result = try self.series.getOrPut(name);
        if (!result.found_existing) {
            result.value_ptr.* = std.ArrayList(TimeSeriesPoint).empty;
        }

        try result.value_ptr.append(self.allocator, .{
            .timestamp = timestamp,
            .value = value,
        });
    }

    /// Export time series to CSV
    pub fn exportCSV(self: *TimeSeriesCollector, output_path: []const u8) !void {
        const file = try Io.Dir.cwd().createFile(self.io, output_path, .{});
        defer file.close(self.io);
        var file_buf: [4096]u8 = undefined;
        var file_writer = file.writer(self.io, &file_buf);
        const w = &file_writer.interface;

        try w.writeAll("benchmark,timestamp,value\n");

        var it = self.series.iterator();
        while (it.next()) |entry| {
            const name = entry.key_ptr.*;
            const points = entry.value_ptr.*;

            for (points.items) |point| {
                var buf: [512]u8 = undefined;
                const line = try std.fmt.bufPrint(&buf, "{s},{d},{d:.2}\n", .{
                    name,
                    point.timestamp,
                    point.value,
                });
                try w.writeAll(line);
            }
        }

        try w.flush();
    }
};

test "PrometheusExporter writes valid label sets" {
    var exporter = PrometheusExporter.init(std.testing.allocator, std.testing.io, "bench");
    defer exporter.deinit();
    const result = bench.BenchmarkResult{
        .name = "parse",
        .samples = .empty,
        .allocator = std.testing.allocator,
        .mean = 10,
        .stddev = 1,
        .min = 9,
        .max = 12,
        .p50 = 10,
        .p75 = 11,
        .p99 = 12,
        .ops_per_sec = 100,
        .iterations = 1,
    };
    var out: Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try exporter.writeMetric(&out.writer, result);
    const text = out.written();
    try std.testing.expect(std.mem.indexOf(u8, text, "bench_duration_nanoseconds{benchmark=\"parse\"} 10\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "bench_ops_per_second{benchmark=\"parse\"} 100.00\n") != null);
}
