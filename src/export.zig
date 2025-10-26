const std = @import("std");
const bench = @import("bench");
const Allocator = std.mem.Allocator;
const BenchmarkResult = bench.BenchmarkResult;

pub const ExportFormat = enum {
    json,
    csv,
};

pub const Exporter = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) Exporter {
        return .{ .allocator = allocator };
    }

    pub fn exportToFile(self: Exporter, results: []const BenchmarkResult, path: []const u8, format: ExportFormat) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        switch (format) {
            .json => try self.writeJson(file, results),
            .csv => try self.writeCsv(file, results),
        }
    }

    fn writeJson(self: Exporter, file: std.fs.File, results: []const BenchmarkResult) !void {
        _ = self;

        try file.writeAll("{\n");
        try file.writeAll("  \"timestamp\": \"");

        // Write current timestamp
        const timestamp = std.time.timestamp();
        var buf: [128]u8 = undefined;
        const ts_str = try std.fmt.bufPrint(&buf, "{d}", .{timestamp});
        try file.writeAll(ts_str);
        try file.writeAll("\",\n");

        try file.writeAll("  \"benchmarks\": [\n");

        for (results, 0..) |result, i| {
            try file.writeAll("    {\n");

            const name_line = try std.fmt.bufPrint(&buf, "      \"name\": \"{s}\",\n", .{result.name});
            try file.writeAll(name_line);

            const mean_line = try std.fmt.bufPrint(&buf, "      \"mean_ns\": {d:.2},\n", .{result.mean});
            try file.writeAll(mean_line);

            const stddev_line = try std.fmt.bufPrint(&buf, "      \"stddev_ns\": {d:.2},\n", .{result.stddev});
            try file.writeAll(stddev_line);

            const min_line = try std.fmt.bufPrint(&buf, "      \"min_ns\": {d},\n", .{result.min});
            try file.writeAll(min_line);

            const max_line = try std.fmt.bufPrint(&buf, "      \"max_ns\": {d},\n", .{result.max});
            try file.writeAll(max_line);

            const p50_line = try std.fmt.bufPrint(&buf, "      \"p50_ns\": {d},\n", .{result.p50});
            try file.writeAll(p50_line);

            const p75_line = try std.fmt.bufPrint(&buf, "      \"p75_ns\": {d},\n", .{result.p75});
            try file.writeAll(p75_line);

            const p99_line = try std.fmt.bufPrint(&buf, "      \"p99_ns\": {d},\n", .{result.p99});
            try file.writeAll(p99_line);

            const ops_line = try std.fmt.bufPrint(&buf, "      \"ops_per_sec\": {d:.2},\n", .{result.ops_per_sec});
            try file.writeAll(ops_line);

            const iter_line = try std.fmt.bufPrint(&buf, "      \"iterations\": {d}\n", .{result.iterations});
            try file.writeAll(iter_line);

            if (i < results.len - 1) {
                try file.writeAll("    },\n");
            } else {
                try file.writeAll("    }\n");
            }
        }

        try file.writeAll("  ]\n");
        try file.writeAll("}\n");
    }

    fn writeCsv(self: Exporter, file: std.fs.File, results: []const BenchmarkResult) !void {
        _ = self;

        // Write header
        try file.writeAll("name,mean_ns,stddev_ns,min_ns,max_ns,p50_ns,p75_ns,p99_ns,ops_per_sec,iterations\n");

        // Write data rows
        var buf: [512]u8 = undefined;
        for (results) |result| {
            const line = try std.fmt.bufPrint(&buf, "{s},{d:.2},{d:.2},{d},{d},{d},{d},{d},{d:.2},{d}\n", .{
                result.name,
                result.mean,
                result.stddev,
                result.min,
                result.max,
                result.p50,
                result.p75,
                result.p99,
                result.ops_per_sec,
                result.iterations,
            });
            try file.writeAll(line);
        }
    }
};
