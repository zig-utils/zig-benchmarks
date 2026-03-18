//! Benchmark Profiling Mode with Detailed Traces
//!
//! Features:
//! - Detailed execution traces
//! - Call stack sampling
//! - Memory allocation tracking
//! - CPU time breakdown
//! - Timeline visualization data
//! - Chrome tracing format support

const std = @import("std");
const bench = @import("bench");
const Allocator = std.mem.Allocator;

/// Trace event type
pub const TraceEventType = enum {
    function_enter,
    function_exit,
    allocation,
    deallocation,
    custom_marker,
};

/// Trace event
pub const TraceEvent = struct {
    event_type: TraceEventType,
    timestamp_ns: u64,
    name: []const u8,
    category: ?[]const u8 = null,
    thread_id: u32,
    duration_ns: ?u64 = null,
    args: ?std.StringHashMap([]const u8) = null,
};

/// Profiling session
pub const ProfilingSession = struct {
    events: std.ArrayList(TraceEvent),
    start_time: u64,
    allocator: Allocator,
    thread_id: u32,

    pub fn init(allocator: Allocator) ProfilingSession {
        const thread_id = @as(u32, @truncate(std.Thread.getCurrentId()));
        return .{
            .events = std.ArrayList(TraceEvent){},
            .start_time = @intCast(std.time.nanoTimestamp()),
            .allocator = allocator,
            .thread_id = thread_id,
        };
    }

    pub fn deinit(self: *ProfilingSession) void {
        self.events.deinit(self.allocator);
    }

    /// Record a function entry
    pub fn recordFunctionEnter(self: *ProfilingSession, name: []const u8) !void {
        try self.events.append(self.allocator, .{
            .event_type = .function_enter,
            .timestamp_ns = @intCast(std.time.nanoTimestamp()),
            .name = name,
            .thread_id = self.thread_id,
        });
    }

    /// Record a function exit
    pub fn recordFunctionExit(self: *ProfilingSession, name: []const u8, duration_ns: u64) !void {
        try self.events.append(self.allocator, .{
            .event_type = .function_exit,
            .timestamp_ns = @intCast(std.time.nanoTimestamp()),
            .name = name,
            .thread_id = self.thread_id,
            .duration_ns = duration_ns,
        });
    }

    /// Record a custom marker
    pub fn recordMarker(self: *ProfilingSession, name: []const u8, category: ?[]const u8) !void {
        try self.events.append(self.allocator, .{
            .event_type = .custom_marker,
            .timestamp_ns = @intCast(std.time.nanoTimestamp()),
            .name = name,
            .category = category,
            .thread_id = self.thread_id,
        });
    }

    /// Export to Chrome Tracing format (JSON)
    pub fn exportChromeTracing(self: *ProfilingSession, output_path: []const u8) !void {
        const file = try std.fs.cwd().createFile(output_path, .{});
        defer file.close();

        try file.writeAll("{\n");
        try file.writeAll("  \"traceEvents\": [\n");

        for (self.events.items, 0..) |event, i| {
            try self.writeChromeEvent(file, &event, i < self.events.items.len - 1);
        }

        try file.writeAll("  ],\n");
        try file.writeAll("  \"displayTimeUnit\": \"ns\"\n");
        try file.writeAll("}\n");
    }

    fn writeChromeEvent(self: *ProfilingSession, file: std.fs.File, event: *const TraceEvent, has_next: bool) !void {
        var buf: [1024]u8 = undefined;

        const ph = switch (event.event_type) {
            .function_enter => "B",
            .function_exit => "E",
            .custom_marker => "i",
            .allocation => "i",
            .deallocation => "i",
        };

        const ts = event.timestamp_ns - self.start_time;

        const line = try std.fmt.bufPrint(&buf,
            \\    {{
            \\      "name": "{s}",
            \\      "ph": "{s}",
            \\      "ts": {d},
            \\      "pid": 1,
            \\      "tid": {d}
        , .{
            event.name,
            ph,
            ts / 1000, // Convert to microseconds for Chrome
            event.thread_id,
        });
        try file.writeAll(line);

        if (event.duration_ns) |dur| {
            const dur_line = try std.fmt.bufPrint(&buf, ",\n      \"dur\": {d}", .{dur / 1000});
            try file.writeAll(dur_line);
        }

        if (event.category) |cat| {
            const cat_line = try std.fmt.bufPrint(&buf, ",\n      \"cat\": \"{s}\"", .{cat});
            try file.writeAll(cat_line);
        }

        if (has_next) {
            try file.writeAll("\n    },\n");
        } else {
            try file.writeAll("\n    }\n");
        }
    }
};

/// Profiling allocator wrapper
pub const ProfilingAllocator = struct {
    parent_allocator: Allocator,
    session: *ProfilingSession,
    total_allocated: usize,
    total_freed: usize,

    pub fn init(parent_allocator: Allocator, session: *ProfilingSession) ProfilingAllocator {
        return .{
            .parent_allocator = parent_allocator,
            .session = session,
            .total_allocated = 0,
            .total_freed = 0,
        };
    }

    pub fn allocator(self: *ProfilingAllocator) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *ProfilingAllocator = @ptrCast(@alignCast(ctx));
        const result = self.parent_allocator.rawAlloc(len, ptr_align, ret_addr);
        if (result) |_| {
            self.total_allocated += len;
            self.session.events.append(self.session.allocator, .{
                .event_type = .allocation,
                .timestamp_ns = @intCast(std.time.nanoTimestamp()),
                .name = "alloc",
                .thread_id = self.session.thread_id,
                .duration_ns = len,
            }) catch {};
        }
        return result;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *ProfilingAllocator = @ptrCast(@alignCast(ctx));
        return self.parent_allocator.rawResize(buf, buf_align, new_len, ret_addr);
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        const self: *ProfilingAllocator = @ptrCast(@alignCast(ctx));
        self.total_freed += buf.len;
        self.session.events.append(self.session.allocator, .{
            .event_type = .deallocation,
            .timestamp_ns = @intCast(std.time.nanoTimestamp()),
            .name = "free",
            .thread_id = self.session.thread_id,
            .duration_ns = buf.len,
        }) catch {};
        self.parent_allocator.rawFree(buf, buf_align, ret_addr);
    }
};

/// Profiling benchmark runner
pub const ProfilingBenchmark = struct {
    name: []const u8,
    func: *const fn () void,
    iterations: u32,
    allocator: Allocator,

    pub fn init(allocator: Allocator, name: []const u8, func: *const fn () void, iterations: u32) ProfilingBenchmark {
        return .{
            .name = name,
            .func = func,
            .iterations = iterations,
            .allocator = allocator,
        };
    }

    /// Run benchmark with profiling
    pub fn run(self: *const ProfilingBenchmark) !ProfilingResult {
        var session = ProfilingSession.init(self.allocator);
        errdefer session.deinit();

        try session.recordMarker("benchmark_start", "benchmark");

        var timer = try std.time.Timer.start();
        var iteration: u32 = 0;
        while (iteration < self.iterations) : (iteration += 1) {
            try session.recordFunctionEnter(self.name);
            const iter_start = timer.read();

            self.func();

            const iter_duration = timer.read() - iter_start;
            try session.recordFunctionExit(self.name, iter_duration);
        }

        try session.recordMarker("benchmark_end", "benchmark");

        return ProfilingResult{
            .name = self.name,
            .session = session,
            .total_iterations = self.iterations,
        };
    }
};

/// Profiling result
pub const ProfilingResult = struct {
    name: []const u8,
    session: ProfilingSession,
    total_iterations: u32,

    pub fn deinit(self: *ProfilingResult) void {
        self.session.deinit();
    }

    /// Export trace to Chrome tracing format
    pub fn exportTrace(self: *ProfilingResult, output_path: []const u8) !void {
        try self.session.exportChromeTracing(output_path);
    }

    /// Print profiling summary
    pub fn printSummary(self: *const ProfilingResult) !void {
        const stdout = std.fs.File.stdout();
        var buf: [512]u8 = undefined;

        const header = try std.fmt.bufPrint(&buf, "\n{s}=== Profiling Summary: {s} ==={s}\n", .{
            bench.Formatter.BOLD,
            self.name,
            bench.Formatter.RESET,
        });
        try stdout.writeAll(header);

        const iterations_line = try std.fmt.bufPrint(&buf, "  Total Iterations: {d}\n", .{self.total_iterations});
        try stdout.writeAll(iterations_line);

        const events_line = try std.fmt.bufPrint(&buf, "  Trace Events: {d}\n", .{self.session.events.items.len});
        try stdout.writeAll(events_line);

        // Count event types
        var function_enters: usize = 0;
        var function_exits: usize = 0;
        var markers: usize = 0;

        for (self.session.events.items) |event| {
            switch (event.event_type) {
                .function_enter => function_enters += 1,
                .function_exit => function_exits += 1,
                .custom_marker => markers += 1,
                else => {},
            }
        }

        const breakdown = try std.fmt.bufPrint(&buf, "  - Function Calls: {d}\n  - Markers: {d}\n", .{
            function_enters,
            markers,
        });
        try stdout.writeAll(breakdown);
    }
};

/// Flame graph data generator
pub const FlameGraphData = struct {
    stacks: std.ArrayList([]const u8),
    allocator: Allocator,

    pub fn init(allocator: Allocator) FlameGraphData {
        return .{
            .stacks = std.ArrayList([]const u8){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FlameGraphData) void {
        for (self.stacks.items) |stack| {
            self.allocator.free(stack);
        }
        self.stacks.deinit(self.allocator);
    }

    /// Add a stack trace sample
    pub fn addStack(self: *FlameGraphData, stack: []const u8) !void {
        const owned = try self.allocator.dupe(u8, stack);
        try self.stacks.append(self.allocator, owned);
    }

    /// Export to flamegraph.pl format
    pub fn exportFlamegraph(self: *FlameGraphData, output_path: []const u8) !void {
        const file = try std.fs.cwd().createFile(output_path, .{});
        defer file.close();

        for (self.stacks.items) |stack| {
            var buf: [1024]u8 = undefined;
            const line = try std.fmt.bufPrint(&buf, "{s} 1\n", .{stack});
            try file.writeAll(line);
        }
    }
};
