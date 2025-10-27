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
    labels: std.StringHashMap([]const u8),

    pub fn init(allocator: Allocator, namespace: []const u8) PrometheusExporter {
        return .{
            .namespace = namespace,
            .allocator = allocator,
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
    pub fn export(self: *PrometheusExporter, results: []const bench.BenchmarkResult, output_path: []const u8) !void {
        const file = try std.fs.cwd().createFile(output_path, .{});
        defer file.close();

        for (results) |result| {
            try self.writeMetric(file, result);
        }
    }

    fn writeMetric(self: *PrometheusExporter, file: std.fs.File, result: bench.BenchmarkResult) !void {
        var buf: [1024]u8 = undefined;

        // Write HELP and TYPE
        const help = try std.fmt.bufPrint(&buf, "# HELP {s}_duration_nanoseconds Benchmark execution time in nanoseconds\n", .{self.namespace});
        try file.writeAll(help);

        const type_line = try std.fmt.bufPrint(&buf, "# TYPE {s}_duration_nanoseconds histogram\n", .{self.namespace});
        try file.writeAll(type_line);

        // Write metrics with labels
        var labels_buf: [512]u8 = undefined;
        var labels_fba = std.heap.FixedBufferAllocator.init(&labels_buf);
        const labels_alloc = labels_fba.allocator();

        var labels_str = std.ArrayList(u8).init(labels_alloc);
        defer labels_str.deinit();

        const writer = labels_str.writer();
        try writer.print("benchmark=\"{s}\"", .{result.name});

        var it = self.labels.iterator();
        while (it.next()) |entry| {
            try writer.print(",{s}=\"{s}\"", .{ entry.key_ptr.*, entry.value_ptr.* });
        }

        // Write mean
        const mean_metric = try std.fmt.bufPrint(&buf, "{s}_duration_nanoseconds{{{}}} {d}\n", .{
            self.namespace,
            labels_str.items,
            result.mean_ns,
        });
        try file.writeAll(mean_metric);

        // Write percentiles as histogram buckets
        const p50_metric = try std.fmt.bufPrint(&buf, "{s}_duration_nanoseconds_bucket{{quantile=\"0.5\",{}}} {d}\n", .{
            self.namespace,
            labels_str.items,
            result.p50_ns,
        });
        try file.writeAll(p50_metric);

        const p75_metric = try std.fmt.bufPrint(&buf, "{s}_duration_nanoseconds_bucket{{quantile=\"0.75\",{}}} {d}\n", .{
            self.namespace,
            labels_str.items,
            result.p75_ns,
        });
        try file.writeAll(p75_metric);

        const p99_metric = try std.fmt.bufPrint(&buf, "{s}_duration_nanoseconds_bucket{{quantile=\"0.99\",{}}} {d}\n", .{
            self.namespace,
            labels_str.items,
            result.p99_ns,
        });
        try file.writeAll(p99_metric);

        // Write ops/sec as gauge
        const ops_help = try std.fmt.bufPrint(&buf, "# HELP {s}_ops_per_second Operations per second\n", .{self.namespace});
        try file.writeAll(ops_help);

        const ops_type = try std.fmt.bufPrint(&buf, "# TYPE {s}_ops_per_second gauge\n", .{self.namespace});
        try file.writeAll(ops_type);

        const ops_metric = try std.fmt.bufPrint(&buf, "{s}_ops_per_second{{{}}} {d:.2}\n", .{
            self.namespace,
            labels_str.items,
            result.ops_per_sec,
        });
        try file.writeAll(ops_metric);

        try file.writeAll("\n");
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
    panels: std.ArrayList(Panel),

    const Panel = struct {
        title: []const u8,
        query: []const u8,
        panel_type: []const u8,
    };

    pub fn init(allocator: Allocator, title: []const u8) GrafanaDashboard {
        return .{
            .title = title,
            .allocator = allocator,
            .panels = std.ArrayList(Panel).init(allocator),
        };
    }

    pub fn deinit(self: *GrafanaDashboard) void {
        self.panels.deinit();
    }

    /// Add a panel to the dashboard
    pub fn addPanel(self: *GrafanaDashboard, title: []const u8, query: []const u8, panel_type: []const u8) !void {
        try self.panels.append(.{
            .title = title,
            .query = query,
            .panel_type = panel_type,
        });
    }

    /// Generate Grafana dashboard JSON
    pub fn generateJSON(self: *GrafanaDashboard, output_path: []const u8) !void {
        const file = try std.fs.cwd().createFile(output_path, .{});
        defer file.close();

        var buf: [4096]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buf);
        const temp_alloc = fba.allocator();

        var json = std.ArrayList(u8).init(temp_alloc);
        defer json.deinit();

        const writer = json.writer();

        try writer.writeAll("{\n");
        try writer.print("  \"title\": \"{s}\",\n", .{self.title});
        try writer.writeAll("  \"editable\": true,\n");
        try writer.writeAll("  \"panels\": [\n");

        for (self.panels.items, 0..) |panel, i| {
            try writer.writeAll("    {\n");
            try writer.print("      \"id\": {d},\n", .{i + 1});
            try writer.print("      \"title\": \"{s}\",\n", .{panel.title});
            try writer.print("      \"type\": \"{s}\",\n", .{panel.panel_type});
            try writer.writeAll("      \"targets\": [\n");
            try writer.writeAll("        {\n");
            try writer.print("          \"expr\": \"{s}\"\n", .{panel.query});
            try writer.writeAll("        }\n");
            try writer.writeAll("      ]\n");
            if (i < self.panels.items.len - 1) {
                try writer.writeAll("    },\n");
            } else {
                try writer.writeAll("    }\n");
            }
        }

        try writer.writeAll("  ]\n");
        try writer.writeAll("}\n");

        try file.writeAll(json.items);
    }

    /// Create a default dashboard for benchmark monitoring
    pub fn createDefaultDashboard(allocator: Allocator, namespace: []const u8) !GrafanaDashboard {
        var dashboard = GrafanaDashboard.init(allocator, "Benchmark Metrics");

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

    pub fn init(allocator: Allocator) TimeSeriesCollector {
        return .{
            .series = std.StringHashMap(std.ArrayList(TimeSeriesPoint)).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TimeSeriesCollector) void {
        var it = self.series.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.series.deinit();
    }

    /// Record a benchmark result
    pub fn record(self: *TimeSeriesCollector, name: []const u8, value: f64) !void {
        const timestamp = std.time.milliTimestamp();

        const result = try self.series.getOrPut(name);
        if (!result.found_existing) {
            result.value_ptr.* = std.ArrayList(TimeSeriesPoint).init(self.allocator);
        }

        try result.value_ptr.append(.{
            .timestamp = timestamp,
            .value = value,
        });
    }

    /// Export time series to CSV
    pub fn exportCSV(self: *TimeSeriesCollector, output_path: []const u8) !void {
        const file = try std.fs.cwd().createFile(output_path, .{});
        defer file.close();

        try file.writeAll("benchmark,timestamp,value\n");

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
                try file.writeAll(line);
            }
        }
    }
};
