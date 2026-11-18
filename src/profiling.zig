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
const Io = std.Io;

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
    io: Io,
    thread_id: u32,

    pub fn init(allocator: Allocator, io: Io) ProfilingSession {
        const thread_id = @as(u32, @truncate(std.Thread.getCurrentId()));
        return .{
            .events = std.ArrayList(TraceEvent).empty,
            .start_time = @intCast(bench.clock.nanoTimestamp(io)),
            .allocator = allocator,
            .io = io,
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
            .timestamp_ns = @intCast(bench.clock.nanoTimestamp(self.io)),
            .name = name,
            .thread_id = self.thread_id,
        });
    }

    /// Record a function exit
    pub fn recordFunctionExit(self: *ProfilingSession, name: []const u8, duration_ns: u64) !void {
        try self.events.append(self.allocator, .{
            .event_type = .function_exit,
            .timestamp_ns = @intCast(bench.clock.nanoTimestamp(self.io)),
            .name = name,
            .thread_id = self.thread_id,
            .duration_ns = duration_ns,
        });
    }

    /// Record a custom marker
    pub fn recordMarker(self: *ProfilingSession, name: []const u8, category: ?[]const u8) !void {
        try self.events.append(self.allocator, .{
            .event_type = .custom_marker,
            .timestamp_ns = @intCast(bench.clock.nanoTimestamp(self.io)),
            .name = name,
            .category = category,
            .thread_id = self.thread_id,
        });
    }

    /// Export to Chrome Tracing format (JSON)
    pub fn exportChromeTracing(self: *ProfilingSession, output_path: []const u8) !void {
        const file = try Io.Dir.cwd().createFile(self.io, output_path, .{});
        defer file.close(self.io);
        var file_buf: [4096]u8 = undefined;
        var file_writer = file.writer(self.io, &file_buf);
        const w = &file_writer.interface;

        try w.writeAll("{\n");
        try w.writeAll("  \"traceEvents\": [\n");

        for (self.events.items, 0..) |event, i| {
            try self.writeChromeEvent(w, &event, i < self.events.items.len - 1);
        }

        try w.writeAll("  ],\n");
        try w.writeAll("  \"displayTimeUnit\": \"ns\"\n");
        try w.writeAll("}\n");

        try w.flush();
    }

    fn writeChromeEvent(self: *ProfilingSession, w: *Io.Writer, event: *const TraceEvent, has_next: bool) !void {
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
        try w.writeAll(line);

        if (event.duration_ns) |dur| {
            const dur_line = try std.fmt.bufPrint(&buf, ",\n      \"dur\": {d}", .{dur / 1000});
            try w.writeAll(dur_line);
        }

        if (event.category) |cat| {
            const cat_line = try std.fmt.bufPrint(&buf, ",\n      \"cat\": \"{s}\"", .{cat});
            try w.writeAll(cat_line);
        }

        if (has_next) {
            try w.writeAll("\n    },\n");
        } else {
            try w.writeAll("\n    }\n");
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
                .remap = remap,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *ProfilingAllocator = @ptrCast(@alignCast(ctx));
        const result = self.parent_allocator.rawAlloc(len, ptr_align, ret_addr);
        if (result) |_| {
            self.total_allocated += len;
            self.session.events.append(self.session.allocator, .{
                .event_type = .allocation,
                .timestamp_ns = @intCast(bench.clock.nanoTimestamp(self.session.io)),
                .name = "alloc",
                .thread_id = self.session.thread_id,
                .duration_ns = len,
            }) catch {};
        }
        return result;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *ProfilingAllocator = @ptrCast(@alignCast(ctx));
        return self.parent_allocator.rawResize(buf, buf_align, new_len, ret_addr);
    }

    fn remap(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *ProfilingAllocator = @ptrCast(@alignCast(ctx));
        return self.parent_allocator.rawRemap(buf, buf_align, new_len, ret_addr);
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        const self: *ProfilingAllocator = @ptrCast(@alignCast(ctx));
        self.total_freed += buf.len;
        self.session.events.append(self.session.allocator, .{
            .event_type = .deallocation,
            .timestamp_ns = @intCast(bench.clock.nanoTimestamp(self.session.io)),
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
    io: Io,

    pub fn init(allocator: Allocator, io: Io, name: []const u8, func: *const fn () void, iterations: u32) ProfilingBenchmark {
        return .{
            .name = name,
            .func = func,
            .iterations = iterations,
            .allocator = allocator,
            .io = io,
        };
    }

    /// Run benchmark with profiling
    pub fn run(self: *const ProfilingBenchmark) !ProfilingResult {
        var session = ProfilingSession.init(self.allocator, self.io);
        errdefer session.deinit();

        try session.recordMarker("benchmark_start", "benchmark");

        var timer = bench.Timer.start(self.io);
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
        var stdout_buf: [512]u8 = undefined;
        var stdout_writer = Io.File.stdout().writerStreaming(self.session.io, &stdout_buf);
        const stdout = &stdout_writer.interface;
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
        try stdout.flush();
    }
};

/// Flame graph data generator
pub const FlameGraphData = struct {
    stacks: std.ArrayList([]const u8),
    allocator: Allocator,
    io: Io,

    pub fn init(allocator: Allocator, io: Io) FlameGraphData {
        return .{
            .stacks = .empty,
            .allocator = allocator,
            .io = io,
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
        const file = try Io.Dir.cwd().createFile(self.io, output_path, .{});
        defer file.close(self.io);
        var file_buf: [4096]u8 = undefined;
        var file_writer = file.writer(self.io, &file_buf);
        const w = &file_writer.interface;

        for (self.stacks.items) |stack| {
            var buf: [1024]u8 = undefined;
            const line = try std.fmt.bufPrint(&buf, "{s} 1\n", .{stack});
            try w.writeAll(line);
        }

        try w.flush();
    }
};
