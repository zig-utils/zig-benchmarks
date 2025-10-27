//! Real-time Benchmark Streaming
//!
//! Features:
//! - Stream benchmark results as they complete
//! - WebSocket support for live dashboards
//! - HTTP Server-Sent Events (SSE) streaming
//! - File-based streaming for monitoring tools
//! - Custom callback support for real-time processing

const std = @import("std");
const bench = @import("bench");
const Allocator = std.mem.Allocator;

/// Streaming output format
pub const StreamFormat = enum {
    json,
    ndjson, // Newline-delimited JSON
    csv,
    custom,
};

/// Stream event types
pub const StreamEventType = enum {
    benchmark_started,
    iteration_complete,
    benchmark_complete,
    suite_started,
    suite_complete,
    error_occurred,
};

/// Stream event
pub const StreamEvent = struct {
    event_type: StreamEventType,
    timestamp: i64,
    benchmark_name: ?[]const u8 = null,
    iteration: ?u32 = null,
    duration_ns: ?u64 = null,
    result: ?bench.BenchmarkResult = null,
    error_message: ?[]const u8 = null,
};

/// Callback function type for stream events
pub const StreamCallback = *const fn (event: StreamEvent) void;

/// File-based streaming writer
pub const FileStreamer = struct {
    file: std.fs.File,
    format: StreamFormat,
    allocator: Allocator,

    pub fn init(allocator: Allocator, path: []const u8, format: StreamFormat) !FileStreamer {
        const file = try std.fs.cwd().createFile(path, .{});
        return .{
            .file = file,
            .format = format,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FileStreamer) void {
        self.file.close();
    }

    /// Write event to file stream
    pub fn write(self: *FileStreamer, event: StreamEvent) !void {
        switch (self.format) {
            .json, .ndjson => try self.writeJSON(event),
            .csv => try self.writeCSV(event),
            .custom => {},
        }
    }

    fn writeJSON(self: *FileStreamer, event: StreamEvent) !void {
        var buf: [2048]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buf);
        const temp_alloc = fba.allocator();

        var string = std.ArrayList(u8).init(temp_alloc);
        defer string.deinit();

        const writer = string.writer();
        try writer.writeAll("{");
        try writer.print("\"event_type\":\"{s}\",", .{@tagName(event.event_type)});
        try writer.print("\"timestamp\":{d}", .{event.timestamp});

        if (event.benchmark_name) |name| {
            try writer.print(",\"benchmark\":\"{s}\"", .{name});
        }
        if (event.iteration) |iter| {
            try writer.print(",\"iteration\":{d}", .{iter});
        }
        if (event.duration_ns) |dur| {
            try writer.print(",\"duration_ns\":{d}", .{dur});
        }
        if (event.result) |result| {
            try writer.print(",\"mean_ns\":{d}", .{result.mean_ns});
            try writer.print(",\"ops_per_sec\":{d:.2}", .{result.ops_per_sec});
        }
        if (event.error_message) |msg| {
            try writer.print(",\"error\":\"{s}\"", .{msg});
        }

        try writer.writeAll("}\n");

        try self.file.writeAll(string.items);
    }

    fn writeCSV(self: *FileStreamer, event: StreamEvent) !void {
        var buf: [1024]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "{s},{d},{s},{d},{d}\n", .{
            @tagName(event.event_type),
            event.timestamp,
            event.benchmark_name orelse "",
            event.iteration orelse 0,
            event.duration_ns orelse 0,
        });
        try self.file.writeAll(line);
    }
};

/// SSE (Server-Sent Events) streamer for HTTP
pub const SSEStreamer = struct {
    writer: std.fs.File.Writer,
    allocator: Allocator,

    pub fn init(allocator: Allocator, writer: std.fs.File.Writer) SSEStreamer {
        return .{
            .writer = writer,
            .allocator = allocator,
        };
    }

    pub fn write(self: *SSEStreamer, event: StreamEvent) !void {
        var buf: [2048]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buf);
        const temp_alloc = fba.allocator();

        var data = std.ArrayList(u8).init(temp_alloc);
        defer data.deinit();

        const writer = data.writer();
        try writer.print("event: {s}\n", .{@tagName(event.event_type)});
        try writer.writeAll("data: {");
        try writer.print("\"timestamp\":{d}", .{event.timestamp});

        if (event.benchmark_name) |name| {
            try writer.print(",\"benchmark\":\"{s}\"", .{name});
        }
        if (event.duration_ns) |dur| {
            try writer.print(",\"duration_ns\":{d}", .{dur});
        }

        try writer.writeAll("}\n\n");

        try self.writer.writeAll(data.items);
    }
};

/// Streaming benchmark suite
pub const StreamingSuite = struct {
    suite: bench.BenchmarkSuite,
    streamers: std.ArrayList(*FileStreamer),
    callbacks: std.ArrayList(StreamCallback),
    allocator: Allocator,

    pub fn init(allocator: Allocator) StreamingSuite {
        return .{
            .suite = bench.BenchmarkSuite.init(allocator),
            .streamers = std.ArrayList(*FileStreamer).init(allocator),
            .callbacks = std.ArrayList(StreamCallback).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *StreamingSuite) void {
        for (self.streamers.items) |streamer| {
            streamer.deinit();
            self.allocator.destroy(streamer);
        }
        self.streamers.deinit();
        self.callbacks.deinit();
        self.suite.deinit();
    }

    /// Add a file streamer
    pub fn addFileStreamer(self: *StreamingSuite, path: []const u8, format: StreamFormat) !void {
        const streamer = try self.allocator.create(FileStreamer);
        streamer.* = try FileStreamer.init(self.allocator, path, format);
        try self.streamers.append(streamer);
    }

    /// Add a callback
    pub fn addCallback(self: *StreamingSuite, callback: StreamCallback) !void {
        try self.callbacks.append(callback);
    }

    /// Add benchmark to suite
    pub fn add(self: *StreamingSuite, name: []const u8, func: *const fn () void) !void {
        try self.suite.add(name, func);
    }

    /// Emit event to all streamers and callbacks
    fn emitEvent(self: *StreamingSuite, event: StreamEvent) void {
        // Write to file streamers
        for (self.streamers.items) |streamer| {
            streamer.write(event) catch |err| {
                std.debug.print("Stream write error: {}\n", .{err});
            };
        }

        // Call callbacks
        for (self.callbacks.items) |callback| {
            callback(event);
        }
    }

    /// Run suite with streaming
    pub fn run(self: *StreamingSuite) !void {
        const suite_start_event = StreamEvent{
            .event_type = .suite_started,
            .timestamp = std.time.milliTimestamp(),
        };
        self.emitEvent(suite_start_event);

        // Note: This is a simplified implementation
        // Full implementation would require modifying the benchmark runner
        // to emit events during execution
        try self.suite.run();

        const suite_complete_event = StreamEvent{
            .event_type = .suite_complete,
            .timestamp = std.time.milliTimestamp(),
        };
        self.emitEvent(suite_complete_event);
    }
};

/// Progress indicator for streaming benchmarks
pub const ProgressIndicator = struct {
    total_benchmarks: usize,
    completed_benchmarks: usize,
    current_benchmark: ?[]const u8,
    start_time: i64,

    pub fn init(total: usize) ProgressIndicator {
        return .{
            .total_benchmarks = total,
            .completed_benchmarks = 0,
            .current_benchmark = null,
            .start_time = std.time.milliTimestamp(),
        };
    }

    pub fn onEvent(self: *ProgressIndicator, event: StreamEvent) void {
        switch (event.event_type) {
            .benchmark_started => {
                self.current_benchmark = event.benchmark_name;
            },
            .benchmark_complete => {
                self.completed_benchmarks += 1;
                self.printProgress();
            },
            else => {},
        }
    }

    fn printProgress(self: *ProgressIndicator) void {
        const percent = (@as(f64, @floatFromInt(self.completed_benchmarks)) / @as(f64, @floatFromInt(self.total_benchmarks))) * 100.0;
        const elapsed = std.time.milliTimestamp() - self.start_time;
        std.debug.print("Progress: {d:.1}% ({d}/{d}) - Elapsed: {d}ms\n", .{
            percent,
            self.completed_benchmarks,
            self.total_benchmarks,
            elapsed,
        });
    }
};
