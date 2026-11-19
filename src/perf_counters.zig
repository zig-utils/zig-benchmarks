//! Per-thread Linux hardware counters. A measurement excludes kernel and
//! hypervisor work. Unavailable counters leave the benchmark runnable.
const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;

pub const Counts = struct {
    cycles: u64 = 0,
    instructions: u64 = 0,
    cache_misses: u64 = 0,
    branch_misses: u64 = 0,

    pub const PerUnit = struct {
        cycles: f64,
        instructions: f64,
        cache_misses: f64,
        branch_misses: f64,
    };

    pub fn add(self: *Counts, other: Counts) void {
        self.cycles +|= other.cycles;
        self.instructions +|= other.instructions;
        self.cache_misses +|= other.cache_misses;
        self.branch_misses +|= other.branch_misses;
    }

    /// The caller defines the unit, such as one iteration or one settled label.
    pub fn perUnit(self: Counts, units: u64) ?PerUnit {
        if (units == 0) return null;
        const n: f64 = @floatFromInt(units);
        return .{
            .cycles = @as(f64, @floatFromInt(self.cycles)) / n,
            .instructions = @as(f64, @floatFromInt(self.instructions)) / n,
            .cache_misses = @as(f64, @floatFromInt(self.cache_misses)) / n,
            .branch_misses = @as(f64, @floatFromInt(self.branch_misses)) / n,
        };
    }
};

const event_count = 4;

pub const Counters = struct {
    fds: [event_count]i32,

    /// Begin a single measurement on the calling thread. Null means the
    /// platform, PMU, or permissions could not supply the full counter group.
    /// Call finish or deinit on the returned handle, which owns its descriptors.
    pub fn start() ?Counters {
        if (builtin.os.tag != .linux) return null;
        return startEvents(.HARDWARE, .{
            @backingInt(linux.PERF.COUNT.HW.CPU_CYCLES),
            @backingInt(linux.PERF.COUNT.HW.INSTRUCTIONS),
            @backingInt(linux.PERF.COUNT.HW.CACHE_MISSES),
            @backingInt(linux.PERF.COUNT.HW.BRANCH_MISSES),
        });
    }

    fn startEvents(event_type: linux.PERF.TYPE, configs: [event_count]u64) ?Counters {
        // linux/perf_event.h: GROUP | TOTAL_TIME_ENABLED | TOTAL_TIME_RUNNING.
        const read_format = (1 << 3) | (1 << 0) | (1 << 1);
        var self: Counters = .{ .fds = @splat(-1) };
        var started = false;
        defer if (!started) self.deinit();
        for (configs, 0..) |config, i| {
            var attr: linux.perf_event_attr = .{
                .type = event_type,
                .config = config,
                .read_format = read_format,
                .flags = .{ .disabled = i == 0, .exclude_kernel = true, .exclude_hv = true },
            };
            const rc = linux.perf_event_open(&attr, 0, -1, self.fds[0], linux.PERF.FLAG.FD_CLOEXEC);
            if (linux.errno(rc) != .SUCCESS) return null;
            self.fds[i] = @intCast(rc);
        }
        started = linux.errno(linux.ioctl(self.fds[0], linux.PERF.EVENT_IOC.ENABLE, linux.PERF.IOC_FLAG_GROUP)) == .SUCCESS;
        return if (started) self else null;
    }

    /// Stop, read and close the group. Null includes groups that never ran.
    pub fn finish(self: *Counters) ?Counts {
        if (builtin.os.tag != .linux or self.fds[0] == -1) return null;
        defer self.deinit();
        if (linux.errno(linux.ioctl(self.fds[0], linux.PERF.EVENT_IOC.DISABLE, linux.PERF.IOC_FLAG_GROUP)) != .SUCCESS)
            return null;
        var words: [3 + event_count]u64 = undefined;
        const bytes = std.mem.asBytes(&words);
        while (true) {
            const rc = linux.read(self.fds[0], bytes.ptr, bytes.len);
            if (linux.errno(rc) == .INTR) continue;
            if (rc != bytes.len) return null;
            return decode(words);
        }
    }

    pub fn deinit(self: *Counters) void {
        if (builtin.os.tag != .linux) return;
        for (&self.fds) |*fd| {
            if (fd.* != -1) _ = linux.close(fd.*);
            fd.* = -1;
        }
    }
};

fn decode(words: [3 + event_count]u64) ?Counts {
    const count, const enabled, const running = words[0..3].*;
    if (count != event_count or running == 0 or running > enabled) return null;
    return .{
        .cycles = scale(words[3], enabled, running),
        .instructions = scale(words[4], enabled, running),
        .cache_misses = scale(words[5], enabled, running),
        .branch_misses = scale(words[6], enabled, running),
    };
}

fn scale(value: u64, enabled: u64, running: u64) u64 {
    if (enabled == running) return value;
    const scaled = (@as(u128, value) * enabled) / running;
    return @intCast(@min(scaled, std.math.maxInt(u64)));
}

test "scale multiplexed counts and report work per unit" {
    const first = decode(.{ 4, 40, 10, 20, 10, 3, 1 }).?;
    var both = first;
    both.add(first);
    const average = both.perUnit(8).?;
    try std.testing.expectEqual(20, average.cycles);
    try std.testing.expectEqual(10, average.instructions);
    try std.testing.expectEqual(3, average.cache_misses);
    try std.testing.expectEqual(1, average.branch_misses);
    try std.testing.expect(both.perUnit(0) == null);
    try std.testing.expect(decode(.{ 4, 40, 0, 0, 0, 0, 0 }) == null);
    try std.testing.expect(decode(.{ 3, 40, 10, 0, 0, 0, 0 }) == null);
}

test "Linux perf group reads counts from one measured thread" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    // Software events exercise the same Linux group ABI on machines without a PMU.
    var region = Counters.startEvents(.SOFTWARE, .{
        @backingInt(linux.PERF.COUNT.SW.TASK_CLOCK),
        @backingInt(linux.PERF.COUNT.SW.CPU_CLOCK),
        @backingInt(linux.PERF.COUNT.SW.PAGE_FAULTS),
        @backingInt(linux.PERF.COUNT.SW.CONTEXT_SWITCHES),
    }) orelse return error.SkipZigTest;
    defer region.deinit();
    for (0..10_000) |i| std.mem.doNotOptimizeAway(i);
    const counts = region.finish() orelse return error.NoPerfCounts;
    try std.testing.expect(counts.cycles > 0);
    try std.testing.expect(counts.instructions > 0);
    try std.testing.expect(region.finish() == null);
}
