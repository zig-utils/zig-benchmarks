const std = @import("std");
const Allocator = std.mem.Allocator;

pub const MemoryStats = struct {
    peak_allocated: usize = 0,
    total_allocated: usize = 0,
    total_freed: usize = 0,
    current_allocated: usize = 0,
    allocation_count: usize = 0,
    free_count: usize = 0,

    pub fn format(self: MemoryStats) [512]u8 {
        var buf: [512]u8 = undefined;
        const formatted = std.fmt.bufPrint(&buf,
            \\  Peak Memory: {d} bytes ({d} KB)
            \\  Total Allocated: {d} bytes
            \\  Total Freed: {d} bytes
            \\  Still Allocated: {d} bytes
            \\  Allocations: {d}
            \\  Frees: {d}
        , .{
            self.peak_allocated,
            self.peak_allocated / 1024,
            self.total_allocated,
            self.total_freed,
            self.current_allocated,
            self.allocation_count,
            self.free_count,
        }) catch unreachable;

        var result: [512]u8 = undefined;
        @memcpy(result[0..formatted.len], formatted);
        @memset(result[formatted.len..], 0);
        return result;
    }
};

pub const ProfilingAllocator = struct {
    parent_allocator: Allocator,
    stats: MemoryStats,

    const Self = @This();

    pub fn init(parent_allocator: Allocator) ProfilingAllocator {
        return .{
            .parent_allocator = parent_allocator,
            .stats = .{},
        };
    }

    pub fn allocator(self: *Self) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
                .remap = remap,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));

        const result = self.parent_allocator.rawAlloc(len, ptr_align, ret_addr);
        if (result) |_| {
            self.stats.total_allocated += len;
            self.stats.current_allocated += len;
            self.stats.allocation_count += 1;

            if (self.stats.current_allocated > self.stats.peak_allocated) {
                self.stats.peak_allocated = self.stats.current_allocated;
            }
        }
        return result;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));

        if (self.parent_allocator.rawResize(buf, buf_align, new_len, ret_addr)) {
            const old_len = buf.len;
            if (new_len > old_len) {
                const diff = new_len - old_len;
                self.stats.total_allocated += diff;
                self.stats.current_allocated += diff;

                if (self.stats.current_allocated > self.stats.peak_allocated) {
                    self.stats.peak_allocated = self.stats.current_allocated;
                }
            } else {
                const diff = old_len - new_len;
                self.stats.total_freed += diff;
                self.stats.current_allocated -= diff;
            }
            return true;
        }
        return false;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));

        self.stats.total_freed += buf.len;
        self.stats.current_allocated -= buf.len;
        self.stats.free_count += 1;

        self.parent_allocator.rawFree(buf, buf_align, ret_addr);
    }

    fn remap(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));

        const result = self.parent_allocator.rawRemap(buf, buf_align, new_len, ret_addr);
        if (result) |_| {
            const old_len = buf.len;
            if (new_len > old_len) {
                const diff = new_len - old_len;
                self.stats.total_allocated += diff;
                self.stats.current_allocated += diff;

                if (self.stats.current_allocated > self.stats.peak_allocated) {
                    self.stats.peak_allocated = self.stats.current_allocated;
                }
            } else {
                const diff = old_len - new_len;
                self.stats.total_freed += diff;
                self.stats.current_allocated -= diff;
            }
        }
        return result;
    }

    pub fn reset(self: *Self) void {
        self.stats = .{};
    }

    pub fn getStats(self: *const Self) MemoryStats {
        return self.stats;
    }
};

pub const MemoryBenchmarkResult = struct {
    name: []const u8,
    time_ns: f64,
    memory_stats: MemoryStats,

    pub fn print(self: MemoryBenchmarkResult, file: std.fs.File) !void {
        var buf: [512]u8 = undefined;

        const header = try std.fmt.bufPrint(&buf, "\n{s}\n", .{self.name});
        try file.writeAll(header);

        const time = try std.fmt.bufPrint(&buf, "  Time: {d:.2} µs\n", .{self.time_ns / 1000.0});
        try file.writeAll(time);

        const stats_str = self.memory_stats.format();
        const null_pos = std.mem.indexOfScalar(u8, &stats_str, 0) orelse stats_str.len;
        try file.writeAll(stats_str[0..null_pos]);
        try file.writeAll("\n");
    }
};
