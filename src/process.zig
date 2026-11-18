//! External-process benchmarking: run a command, drive it, and sample its memory.
//!
//! The allocator-level `memory_profiler` only sees bytes that pass through a Zig
//! `Allocator`. It cannot see mmapped data, page cache, or memory a separate
//! program uses. This module measures a child process from the outside, the way
//! the operating system accounts for it:
//!
//! - Linux: `/proc/<pid>/smaps_rollup` (Rss, Pss, Private/Shared Clean/Dirty,
//!   Anonymous, SwapPss).
//! - macOS: `proc_pid_rusage` (`phys_footprint` and resident size). macOS has no
//!   PSS or per-page clean/dirty split for another process without a task port,
//!   so `private_dirty` is the footprint (dirty plus compressed memory, which is
//!   what the kernel charges the process for) and `private_clean` is the resident
//!   size the footprint does not cover.
//!
//! File-backed pages that only one process maps show up as private *clean* on
//! Linux, so gate on dirty memory, not on RSS.
//!
//! Memory of the child's own children is not included.

const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Child = std.process.Child;

const native_os = builtin.os.tag;
const is_linux = native_os == .linux;
const is_darwin = native_os.isDarwin();

/// Whether this platform can sample another process's memory.
pub const supported = is_linux or is_darwin;

/// A memory metric. Values are bytes.
pub const Metric = enum {
    /// Resident set size.
    rss,
    /// Proportional set size: shared pages divided among the processes that map them. Linux only.
    pss,
    /// Private pages that match their backing store (for example a read-only file mapping).
    private_clean,
    /// Private pages that were written to. The figure to gate on.
    private_dirty,
    /// Shared pages that match their backing store. Linux only.
    shared_clean,
    /// Shared pages that were written to. Linux only.
    shared_dirty,
    /// Anonymous (not file-backed) memory. Linux only.
    anonymous,
    /// Proportional swap usage. Linux only.
    swap_pss,
    /// Physical footprint as the macOS kernel charges it. macOS only.
    phys_footprint,

    pub const all = std.enums.values(Metric);
};

/// One memory reading. A metric is `null` when the platform does not report it.
pub const Values = struct {
    rss: ?u64 = null,
    pss: ?u64 = null,
    private_clean: ?u64 = null,
    private_dirty: ?u64 = null,
    shared_clean: ?u64 = null,
    shared_dirty: ?u64 = null,
    anonymous: ?u64 = null,
    swap_pss: ?u64 = null,
    phys_footprint: ?u64 = null,

    pub fn get(self: Values, metric: Metric) ?u64 {
        return switch (metric) {
            inline else => |m| @field(self, @tagName(m)),
        };
    }
};

/// A reading taken `t_ns` nanoseconds after the child was spawned.
pub const Sample = struct {
    t_ns: u64,
    values: Values,
};

/// Peak, median and friends of one metric over every sample that reported it.
pub const Summary = struct {
    count: usize,
    min: u64,
    max: u64,
    median: u64,
    mean: u64,

    /// Alias for `max`: the highest sampled value.
    pub fn peak(self: Summary) u64 {
        return self.max;
    }
};

/// What happens to a child's stdout or stderr.
pub const Output = enum { inherit, ignore };

/// How the child is fed while it runs. Driving happens concurrently with sampling.
pub const Driver = union(enum) {
    /// Nothing: stdin is `/dev/null`.
    none,
    /// Write these bytes to the child's stdin, then close it.
    stdin_bytes: []const u8,
    /// Stream this file to the child's stdin, then close it.
    stdin_file: []const u8,
    /// Connect to a Unix socket the child listens on, send `request`, close the
    /// write side and read the response until the child closes the connection.
    unix_socket: UnixSocket,

    pub const UnixSocket = struct {
        path: []const u8,
        request: []const u8 = "",
        /// How long to keep retrying while the child has not started listening.
        connect_timeout_ns: u64 = 5 * std.time.ns_per_s,
    };
};

pub const Options = struct {
    /// The command and its arguments. `argv[0]` is resolved through PATH.
    argv: []const []const u8,
    /// Memory samples per second.
    sample_hz: u32 = 10,
    driver: Driver = .none,
    stdout: Output = .ignore,
    stderr: Output = .inherit,
    cwd: Child.Cwd = .inherit,
    environ_map: ?*const std.process.Environ.Map = null,
    /// Kill the child with SIGKILL once it has run this long.
    timeout_ns: ?u64 = null,
};

/// Bytes the driver moved.
pub const DriverStats = struct {
    bytes_written: u64 = 0,
    bytes_read: u64 = 0,
};

pub const Result = struct {
    allocator: Allocator,
    /// Copy of the command line.
    argv: []const []const u8,
    sample_hz: u32,
    samples: []Sample,
    /// Per-metric summary over `samples`; null where no sample reported the metric.
    summaries: std.EnumArray(Metric, ?Summary),
    term: Child.Term,
    timed_out: bool,
    /// Spawn to exit, on the monotonic clock.
    wall_ns: u64,
    user_cpu_ns: ?u64,
    system_cpu_ns: ?u64,
    minor_faults: ?u64,
    major_faults: ?u64,
    /// Peak RSS as the kernel tracked it (wait4 `ru_maxrss`), independent of sampling.
    max_rss: ?u64,
    driver: DriverStats,

    pub fn deinit(self: *Result) void {
        for (self.argv) |arg| self.allocator.free(arg);
        self.allocator.free(self.argv);
        self.allocator.free(self.samples);
        self.* = undefined;
    }

    /// Summary of `metric` over the samples, or null if no sample reported it.
    pub fn summary(self: *const Result, metric: Metric) ?Summary {
        return self.summaries.get(metric);
    }

    /// Statistic of `metric`, or null if no sample reported it.
    pub fn stat(self: *const Result, metric: Metric, which: Stat) ?u64 {
        const s = self.summary(metric) orelse return null;
        return switch (which) {
            .peak => s.max,
            .median => s.median,
            .mean => s.mean,
            .min => s.min,
        };
    }

    /// Check every gate. Returns `error.GateExceeded` if any metric is over its
    /// threshold and `error.MetricUnavailable` if a gated metric was never sampled
    /// (so an unsupported metric cannot pass silently). `report` gets one line per gate.
    pub fn enforce(self: *const Result, gates: []const Gate, report: ?*Io.Writer) !void {
        var failed: ?anyerror = null;
        for (gates) |gate| {
            const outcome = gate.check(self);
            if (report) |w| try outcome.print(w);
            switch (outcome.status) {
                .pass => {},
                .exceeded => failed = failed orelse error.GateExceeded,
                .unavailable => failed = failed orelse error.MetricUnavailable,
            }
        }
        if (failed) |err| return err;
    }

    /// Write the result as one JSON object.
    pub fn writeJson(self: *const Result, w: *Io.Writer) !void {
        var s: std.json.Stringify = .{ .writer = w, .options = .{ .whitespace = .indent_2 } };
        try s.beginObject();

        try s.objectField("command");
        try s.write(self.argv);

        try s.objectField("exit");
        try s.beginObject();
        switch (self.term) {
            .exited => |code| {
                try s.objectField("code");
                try s.write(code);
            },
            .signal => |sig| {
                try s.objectField("signal");
                try s.write(@backingInt(sig));
            },
            .stopped => |sig| {
                try s.objectField("stopped");
                try s.write(@backingInt(sig));
            },
            .unknown => |status| {
                try s.objectField("unknown");
                try s.write(status);
            },
        }
        try s.endObject();

        try s.objectField("timed_out");
        try s.write(self.timed_out);
        try s.objectField("wall_ns");
        try s.write(self.wall_ns);
        try s.objectField("user_cpu_ns");
        try s.write(self.user_cpu_ns);
        try s.objectField("system_cpu_ns");
        try s.write(self.system_cpu_ns);
        try s.objectField("minor_faults");
        try s.write(self.minor_faults);
        try s.objectField("major_faults");
        try s.write(self.major_faults);
        try s.objectField("max_rss");
        try s.write(self.max_rss);
        try s.objectField("driver");
        try s.write(self.driver);
        try s.objectField("sample_hz");
        try s.write(self.sample_hz);
        try s.objectField("sample_count");
        try s.write(self.samples.len);

        try s.objectField("metrics");
        try s.beginObject();
        for (Metric.all) |metric| {
            const sum = self.summary(metric) orelse continue;
            try s.objectField(@tagName(metric));
            try s.beginObject();
            try s.objectField("peak");
            try s.write(sum.max);
            try s.objectField("median");
            try s.write(sum.median);
            try s.objectField("mean");
            try s.write(sum.mean);
            try s.objectField("min");
            try s.write(sum.min);
            try s.endObject();
        }
        try s.endObject();

        try s.objectField("samples");
        try s.beginArray();
        for (self.samples) |sample| {
            try s.beginObject();
            try s.objectField("t_ns");
            try s.write(sample.t_ns);
            for (Metric.all) |metric| {
                const v = sample.values.get(metric) orelse continue;
                try s.objectField(@tagName(metric));
                try s.write(v);
            }
            try s.endObject();
        }
        try s.endArray();

        try s.endObject();
    }
};

/// Which statistic a gate compares.
pub const Stat = enum { peak, median, mean, min };

/// Fail when a metric's statistic exceeds `max_bytes`.
pub const Gate = struct {
    metric: Metric,
    stat: Stat = .peak,
    max_bytes: u64,

    pub const Outcome = struct {
        gate: Gate,
        observed: ?u64,
        status: enum { pass, exceeded, unavailable },

        pub fn print(self: Outcome, w: *Io.Writer) !void {
            const verdict = switch (self.status) {
                .pass => "pass",
                .exceeded => "FAIL",
                .unavailable => "FAIL (not sampled)",
            };
            try w.print("{s} {s} {s}: ", .{ verdict, @tagName(self.gate.metric), @tagName(self.gate.stat) });
            if (self.observed) |v| try w.print("{d}", .{v}) else try w.writeAll("n/a");
            try w.print(" <= {d}\n", .{self.gate.max_bytes});
        }
    };

    pub fn check(self: Gate, result: *const Result) Outcome {
        const observed = result.stat(self.metric, self.stat);
        const status: @FieldType(Outcome, "status") = if (observed) |v|
            (if (v <= self.max_bytes) .pass else .exceeded)
        else
            .unavailable;
        return .{ .gate = self, .observed = observed, .status = status };
    }
};

pub const RunError = error{
    UnsupportedPlatform,
    InvalidSampleRate,
    /// A sample could not be read for a reason other than the child exiting.
    SampleFailed,
} || std.process.SpawnError || Child.WaitError || Io.ConcurrentError || Allocator.Error;

/// Run `options.argv`, drive it, and sample its memory until it exits.
///
/// Needs an `Io` that supports `concurrent` (for example `std.Io.Threaded`):
/// the child is waited on and driven in their own tasks while this one samples.
/// A driver error does not abort the run; the child keeps running until it exits.
pub fn run(gpa: Allocator, io: Io, options: Options) RunError!Result {
    if (!supported) return error.UnsupportedPlatform;
    if (options.sample_hz == 0) return error.InvalidSampleRate;
    const interval_ns: i96 = @max(1, std.time.ns_per_s / options.sample_hz);

    const argv_copy = try gpa.alloc([]const u8, options.argv.len);
    var copied: usize = 0;
    errdefer {
        for (argv_copy[0..copied]) |arg| gpa.free(arg);
        gpa.free(argv_copy);
    }
    for (options.argv, 0..) |arg, i| {
        argv_copy[i] = try gpa.dupe(u8, arg);
        copied += 1;
    }

    var samples: std.ArrayList(Sample) = .empty;
    errdefer samples.deinit(gpa);

    const wants_stdin = switch (options.driver) {
        .stdin_bytes, .stdin_file => true,
        .none, .unix_socket => false,
    };

    var child = try std.process.spawn(io, .{
        .argv = options.argv,
        .cwd = options.cwd,
        .environ_map = options.environ_map,
        .stdin = if (wants_stdin) .pipe else .ignore,
        .stdout = stdio(options.stdout),
        .stderr = stdio(options.stderr),
        .request_resource_usage_statistics = true,
    });
    const started = Io.Clock.Timestamp.now(io, .awake);
    const pid = child.id.?;

    var shared: Shared = .{};

    // The waiter only observes the exit (WNOWAIT): the child stays a zombie, so
    // its pid cannot be reused while we still sample it. `child.wait` reaps it.
    var waiter = io.concurrent(waitForExit, .{ io, pid, &shared }) catch |err| {
        child.kill(io);
        return err;
    };

    // The driver owns stdin from here: it closes it when done.
    const stdin_file = child.stdin;
    child.stdin = null;
    var driver_future: ?Io.Future(DriverStats) = null;
    if (options.driver != .none) {
        driver_future = io.concurrent(drive, .{ io, options.driver, stdin_file, &shared }) catch |err| {
            if (stdin_file) |f| f.close(io);
            killNoReap(pid);
            waiter.await(io);
            _ = child.wait(io) catch {};
            return err;
        };
    }

    var timed_out = false;
    var sample_error = false;
    var next = started;
    while (true) {
        const now = Io.Clock.Timestamp.now(io, .awake);
        const elapsed = nonNegative(started.durationTo(now).raw.nanoseconds);

        if (readValues(pid)) |maybe| {
            if (maybe) |values| {
                samples.append(gpa, .{ .t_ns = elapsed, .values = values }) catch {
                    sample_error = true;
                    killNoReap(pid);
                };
            }
        } else |_| if (!shared.exited.isSet()) {
            sample_error = true;
            killNoReap(pid);
        }

        if (shared.exited.isSet()) break;

        if (options.timeout_ns) |limit| {
            if (elapsed >= limit and !timed_out) {
                timed_out = true;
                killNoReap(pid);
            }
        }

        next = next.addDuration(.{ .raw = .fromNanoseconds(interval_ns), .clock = .awake });
        // Fell behind (a slow sample or a stalled scheduler): skip, do not burst.
        if (next.compare(.lt, now)) next = now;
        shared.exited.waitTimeout(io, .{ .deadline = next }) catch {};
    }

    waiter.await(io);
    const driver_stats: DriverStats = if (driver_future) |*f| f.await(io) else .{};
    const term = try child.wait(io);

    if (sample_error) return error.SampleFailed;

    const summaries = try summarizeAll(gpa, samples.items);
    const exit_at = shared.exit_at orelse Io.Clock.Timestamp.now(io, .awake);
    var result: Result = .{
        .allocator = gpa,
        .argv = argv_copy,
        .sample_hz = options.sample_hz,
        .samples = try samples.toOwnedSlice(gpa),
        .summaries = summaries,
        .term = term,
        .timed_out = timed_out,
        .wall_ns = nonNegative(started.durationTo(exit_at).raw.nanoseconds),
        .user_cpu_ns = null,
        .system_cpu_ns = null,
        .minor_faults = null,
        .major_faults = null,
        .max_rss = child.resource_usage_statistics.getMaxRss(),
        .driver = driver_stats,
    };
    if (child.resource_usage_statistics.rusage) |ru| {
        result.user_cpu_ns = timevalNs(ru.utime);
        result.system_cpu_ns = timevalNs(ru.stime);
        result.minor_faults = @intCast(@max(0, ru.minflt));
        result.major_faults = @intCast(@max(0, ru.majflt));
    }
    return result;
}

/// Summarize every metric over `samples`.
pub fn summarizeAll(gpa: Allocator, samples: []const Sample) Allocator.Error!std.EnumArray(Metric, ?Summary) {
    var out: std.EnumArray(Metric, ?Summary) = .initFill(null);
    for (Metric.all) |metric| out.set(metric, try summarize(gpa, samples, metric));
    return out;
}

/// Summarize `metric` over `samples`. `gpa` holds a scratch copy for the median.
pub fn summarize(gpa: Allocator, samples: []const Sample, metric: Metric) Allocator.Error!?Summary {
    var values: std.ArrayList(u64) = .empty;
    defer values.deinit(gpa);
    for (samples) |sample| {
        if (sample.values.get(metric)) |v| try values.append(gpa, v);
    }
    return summarizeValues(values.items);
}

/// Summarize raw values; sorts `values` in place.
pub fn summarizeValues(values: []u64) ?Summary {
    if (values.len == 0) return null;
    std.mem.sort(u64, values, {}, std.sort.asc(u64));
    var total: u128 = 0;
    for (values) |v| total += v;
    const mid = values.len / 2;
    const median = if (values.len % 2 == 1)
        values[mid]
    else
        @as(u64, @intCast((@as(u128, values[mid - 1]) + values[mid]) / 2));
    return .{
        .count = values.len,
        .min = values[0],
        .max = values[values.len - 1],
        .median = median,
        .mean = @intCast(total / values.len),
    };
}

/// Parse the text of `/proc/<pid>/smaps_rollup` (also accepts `/proc/<pid>/smaps`
/// lines, summing repeated keys). Returns null when there is no `Rss` line, which
/// is what an exited process looks like.
pub fn parseSmapsRollup(text: []const u8) ?Values {
    var values: Values = .{};
    var saw_rss = false;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const key = line[0..colon];
        var rest = std.mem.trim(u8, line[colon + 1 ..], " \t");
        if (!std.mem.endsWith(u8, rest, " kB")) continue;
        rest = std.mem.trimEnd(u8, rest[0 .. rest.len - 3], " ");
        const kib = std.fmt.parseInt(u64, rest, 10) catch continue;
        const bytes = kib * 1024;
        const field: ?*?u64 = if (std.mem.eql(u8, key, "Rss"))
            &values.rss
        else if (std.mem.eql(u8, key, "Pss"))
            &values.pss
        else if (std.mem.eql(u8, key, "Private_Clean"))
            &values.private_clean
        else if (std.mem.eql(u8, key, "Private_Dirty"))
            &values.private_dirty
        else if (std.mem.eql(u8, key, "Shared_Clean"))
            &values.shared_clean
        else if (std.mem.eql(u8, key, "Shared_Dirty"))
            &values.shared_dirty
        else if (std.mem.eql(u8, key, "Anonymous"))
            &values.anonymous
        else if (std.mem.eql(u8, key, "SwapPss"))
            &values.swap_pss
        else
            null;
        if (field) |f| {
            f.* = (f.* orelse 0) + bytes;
            if (f == &values.rss) saw_rss = true;
        }
    }
    return if (saw_rss) values else null;
}

const Shared = struct {
    exited: Io.Event = .unset,
    /// Written before `exited` is set.
    exit_at: ?Io.Clock.Timestamp = null,
};

fn stdio(output: Output) std.process.SpawnOptions.StdIo {
    return switch (output) {
        .inherit => .inherit,
        .ignore => .ignore,
    };
}

fn nonNegative(ns: i96) u64 {
    if (ns <= 0) return 0;
    return std.math.cast(u64, ns) orelse std.math.maxInt(u64);
}

fn timevalNs(tv: anytype) u64 {
    const sec: u64 = @intCast(@max(0, tv.sec));
    const usec: u64 = @intCast(@max(0, tv.usec));
    return sec * std.time.ns_per_s + usec * std.time.ns_per_us;
}

/// SIGKILL without reaping, so the waiter and `child.wait` still see the exit.
fn killNoReap(pid: std.posix.pid_t) void {
    std.posix.kill(pid, .KILL) catch {};
}

fn waitForExit(io: Io, pid: std.posix.pid_t, shared: *Shared) void {
    waitNoReap(pid);
    shared.exit_at = Io.Clock.Timestamp.now(io, .awake);
    shared.exited.set(io);
}

/// Block until `pid` exits, leaving it waitable.
fn waitNoReap(pid: std.posix.pid_t) void {
    if (is_linux) {
        const linux = std.os.linux;
        var info: linux.siginfo_t = undefined;
        while (true) switch (linux.errno(linux.waitid(.PID, pid, &info, linux.W.EXITED | linux.W.NOWAIT, null))) {
            .INTR => continue,
            else => return, // exited, or already reaped (CHILD)
        };
    } else if (is_darwin) {
        var info: std.c.siginfo_t = undefined;
        while (true) {
            if (darwin.waitid(darwin.P_PID, @intCast(pid), &info, darwin.WEXITED | darwin.WNOWAIT) == 0) return;
            if (std.posix.errno(-1) != .INTR) return;
        }
    } else unreachable;
}

const darwin = struct {
    const P_PID: c_int = 1;
    const WEXITED: c_int = 0x00000004;
    const WNOWAIT: c_int = 0x00000020;
    const RUSAGE_INFO_V4: c_int = 4;

    extern "c" fn waitid(idtype: c_int, id: u32, infop: *std.c.siginfo_t, options: c_int) c_int;
    extern "c" fn proc_pid_rusage(pid: c_int, flavor: c_int, buffer: *rusage_info_v4) c_int;

    /// `struct rusage_info_v4` from <sys/resource.h>.
    const rusage_info_v4 = extern struct {
        ri_uuid: [16]u8,
        ri_user_time: u64,
        ri_system_time: u64,
        ri_pkg_idle_wkups: u64,
        ri_interrupt_wkups: u64,
        ri_pageins: u64,
        ri_wired_size: u64,
        ri_resident_size: u64,
        ri_phys_footprint: u64,
        ri_proc_start_abstime: u64,
        ri_proc_exit_abstime: u64,
        ri_child_user_time: u64,
        ri_child_system_time: u64,
        ri_child_pkg_idle_wkups: u64,
        ri_child_interrupt_wkups: u64,
        ri_child_pageins: u64,
        ri_child_elapsed_abstime: u64,
        ri_diskio_bytesread: u64,
        ri_diskio_byteswritten: u64,
        ri_cpu_time_qos_default: u64,
        ri_cpu_time_qos_maintenance: u64,
        ri_cpu_time_qos_background: u64,
        ri_cpu_time_qos_utility: u64,
        ri_cpu_time_qos_legacy: u64,
        ri_cpu_time_qos_user_initiated: u64,
        ri_cpu_time_qos_user_interactive: u64,
        ri_billed_system_time: u64,
        ri_serviced_system_time: u64,
        ri_logical_writes: u64,
        ri_lifetime_max_phys_footprint: u64,
        ri_instructions: u64,
        ri_cycles: u64,
        ri_billed_energy: u64,
        ri_serviced_energy: u64,
        ri_interval_max_phys_footprint: u64,
        ri_runnable_time: u64,
    };
};

/// Read the child's memory now. Null means the child has exited and has no
/// memory left to report.
fn readValues(pid: std.posix.pid_t) error{SampleFailed}!?Values {
    if (is_linux) return readLinux(pid);
    if (is_darwin) return readDarwin(pid);
    unreachable;
}

fn readLinux(pid: std.posix.pid_t) error{SampleFailed}!?Values {
    const linux = std.os.linux;
    var path_buf: [64]u8 = undefined;
    const path = std.fmt.bufPrintSentinel(&path_buf, "/proc/{d}/smaps_rollup", .{pid}, 0) catch unreachable;

    // Raw syscalls: a process that exits mid-read makes read() fail with ESRCH,
    // which must count as "exited", not as an I/O error.
    const open_rc = linux.open(path.ptr, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    switch (linux.errno(open_rc)) {
        .SUCCESS => {},
        .SRCH, .NOENT => return null,
        else => return error.SampleFailed,
    }
    const fd: linux.fd_t = @intCast(open_rc);
    defer _ = linux.close(fd);

    var buf: [4096]u8 = undefined;
    var len: usize = 0;
    while (len < buf.len) {
        const rc = linux.read(fd, buf[len..].ptr, buf.len - len);
        switch (linux.errno(rc)) {
            .SUCCESS => {
                if (rc == 0) break;
                len += rc;
            },
            .INTR => continue,
            .SRCH => return null,
            else => return error.SampleFailed,
        }
    }
    return parseSmapsRollup(buf[0..len]);
}

fn readDarwin(pid: std.posix.pid_t) error{SampleFailed}!?Values {
    var info: darwin.rusage_info_v4 = undefined;
    if (darwin.proc_pid_rusage(pid, darwin.RUSAGE_INFO_V4, &info) != 0) {
        return switch (std.posix.errno(-1)) {
            .SRCH => null,
            else => error.SampleFailed,
        };
    }
    // An exited (zombie) process reports its final numbers with a nonzero exit
    // time and no resident memory; it is not a live sample.
    if (info.ri_proc_exit_abstime != 0) return null;
    const footprint = info.ri_phys_footprint;
    const resident = info.ri_resident_size;
    return .{
        .rss = resident,
        .phys_footprint = footprint,
        .private_dirty = footprint,
        .private_clean = resident -| footprint,
    };
}

fn drive(io: Io, driver: Driver, stdin_file: ?Io.File, shared: *Shared) DriverStats {
    var stats: DriverStats = .{};
    switch (driver) {
        .none => {},
        .stdin_bytes => |bytes| {
            const file = stdin_file.?;
            defer file.close(io);
            file.writeStreamingAll(io, bytes) catch return stats;
            stats.bytes_written = bytes.len;
        },
        .stdin_file => |path| {
            const file = stdin_file.?;
            defer file.close(io);
            const source = Io.Dir.cwd().openFile(io, path, .{}) catch return stats;
            defer source.close(io);
            var read_buf: [64 * 1024]u8 = undefined;
            var reader = source.readerStreaming(io, &read_buf);
            var write_buf: [64 * 1024]u8 = undefined;
            var writer = file.writerStreaming(io, &write_buf);
            stats.bytes_written = reader.interface.streamRemaining(&writer.interface) catch return stats;
            writer.interface.flush() catch {};
        },
        .unix_socket => |sock| driveSocket(io, sock, shared, &stats),
    }
    return stats;
}

fn driveSocket(io: Io, sock: Driver.UnixSocket, shared: *Shared, stats: *DriverStats) void {
    const address = Io.net.UnixAddress.init(sock.path) catch return;
    const deadline = Io.Clock.Timestamp.fromNow(io, .{
        .raw = .fromNanoseconds(@intCast(sock.connect_timeout_ns)),
        .clock = .awake,
    });
    const stream = while (true) {
        if (address.connect(io)) |stream| break stream else |err| switch (err) {
            error.FileNotFound, error.ConnectionRefused => {
                if (shared.exited.isSet()) return;
                if (deadline.compare(.lt, Io.Clock.Timestamp.now(io, .awake))) return;
                io.sleep(.fromMilliseconds(5), .awake) catch return;
            },
            else => return,
        }
    };
    defer stream.close(io);

    var write_buf: [4096]u8 = undefined;
    var writer = stream.writer(io, &write_buf);
    writer.interface.writeAll(sock.request) catch return;
    writer.interface.flush() catch return;
    stats.bytes_written = sock.request.len;
    stream.shutdown(io, .send) catch {};

    // Counted with readSliceShort, not discardRemaining: the 0.17 streaming
    // readers can drop the bytes still buffered at end of stream from the count.
    var read_buf: [4096]u8 = undefined;
    var reader = stream.reader(io, &read_buf);
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = reader.interface.readSliceShort(&buf) catch return;
        stats.bytes_read += n;
        if (n < buf.len) return;
    }
}

test "parseSmapsRollup reads the fields in bytes" {
    const text =
        \\55d0c0a00000-7ffd8a5f2000 ---p 00000000 00:00 0                          [rollup]
        \\Rss:               69632 kB
        \\Pss:               66001 kB
        \\Pss_Anon:          65600 kB
        \\Shared_Clean:       3600 kB
        \\Shared_Dirty:          0 kB
        \\Private_Clean:       432 kB
        \\Private_Dirty:     65600 kB
        \\Referenced:        69632 kB
        \\Anonymous:         65600 kB
        \\Swap:                  0 kB
        \\SwapPss:              12 kB
        \\Locked:                0 kB
    ;
    const v = parseSmapsRollup(text).?;
    try std.testing.expectEqual(@as(?u64, 69632 * 1024), v.rss);
    try std.testing.expectEqual(@as(?u64, 66001 * 1024), v.pss);
    try std.testing.expectEqual(@as(?u64, 65600 * 1024), v.private_dirty);
    try std.testing.expectEqual(@as(?u64, 432 * 1024), v.private_clean);
    try std.testing.expectEqual(@as(?u64, 3600 * 1024), v.shared_clean);
    try std.testing.expectEqual(@as(?u64, 0), v.shared_dirty);
    try std.testing.expectEqual(@as(?u64, 65600 * 1024), v.anonymous);
    try std.testing.expectEqual(@as(?u64, 12 * 1024), v.swap_pss);
    try std.testing.expectEqual(@as(?u64, null), v.phys_footprint);
}

test "parseSmapsRollup: no Rss line means no sample" {
    try std.testing.expectEqual(@as(?Values, null), parseSmapsRollup(""));
    try std.testing.expectEqual(@as(?Values, null), parseSmapsRollup("[rollup]\n"));
}

test "summarizeValues: peak, median, mean" {
    var odd = [_]u64{ 5, 1, 9, 3, 7 };
    const a = summarizeValues(&odd).?;
    try std.testing.expectEqual(@as(u64, 9), a.peak());
    try std.testing.expectEqual(@as(u64, 5), a.median);
    try std.testing.expectEqual(@as(u64, 1), a.min);
    try std.testing.expectEqual(@as(u64, 5), a.mean);

    var even = [_]u64{ 4, 2, 8, 6 };
    try std.testing.expectEqual(@as(u64, 5), summarizeValues(&even).?.median);

    var none = [_]u64{};
    try std.testing.expectEqual(@as(?Summary, null), summarizeValues(&none));
}

fn fakeResult(gpa: Allocator, samples: []Sample) !Result {
    const argv = try gpa.alloc([]const u8, 1);
    argv[0] = try gpa.dupe(u8, "fake");
    return .{
        .allocator = gpa,
        .argv = argv,
        .sample_hz = 10,
        .samples = try gpa.dupe(Sample, samples),
        .summaries = try summarizeAll(gpa, samples),
        .term = .{ .exited = 0 },
        .timed_out = false,
        .wall_ns = 300,
        .user_cpu_ns = 10,
        .system_cpu_ns = 20,
        .minor_faults = 1,
        .major_faults = 0,
        .max_rss = 3000,
        .driver = .{},
    };
}

test "gates pass, fail, and refuse metrics that were never sampled" {
    const gpa = std.testing.allocator;
    var samples = [_]Sample{
        .{ .t_ns = 0, .values = .{ .rss = 1000, .private_dirty = 100 } },
        .{ .t_ns = 100, .values = .{ .rss = 3000, .private_dirty = 900 } },
        .{ .t_ns = 200, .values = .{ .rss = 2000, .private_dirty = 500 } },
    };
    var result = try fakeResult(gpa, &samples);
    defer result.deinit();

    try result.enforce(&.{.{ .metric = .private_dirty, .max_bytes = 900 }}, null);
    try result.enforce(&.{.{ .metric = .private_dirty, .stat = .median, .max_bytes = 500 }}, null);
    try std.testing.expectError(
        error.GateExceeded,
        result.enforce(&.{.{ .metric = .private_dirty, .max_bytes = 899 }}, null),
    );
    try std.testing.expectError(
        error.MetricUnavailable,
        result.enforce(&.{.{ .metric = .pss, .max_bytes = 1 << 40 }}, null),
    );

    var buf: [256]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try std.testing.expectError(
        error.GateExceeded,
        result.enforce(&.{.{ .metric = .rss, .max_bytes = 2500 }}, &w),
    );
    try std.testing.expectEqualStrings("FAIL rss peak: 3000 <= 2500\n", w.buffered());
}

test "writeJson emits summaries and the time series" {
    const gpa = std.testing.allocator;
    var samples = [_]Sample{
        .{ .t_ns = 0, .values = .{ .rss = 1000, .private_dirty = 100 } },
        .{ .t_ns = 100, .values = .{ .rss = 3000, .private_dirty = 900 } },
    };
    var result = try fakeResult(gpa, &samples);
    defer result.deinit();

    var out: Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try result.writeJson(&out.writer);

    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, out.written(), .{});
    defer parsed.deinit();
    const root = parsed.value.object;
    try std.testing.expectEqual(@as(i64, 0), root.get("exit").?.object.get("code").?.integer);
    try std.testing.expectEqual(@as(i64, 2), root.get("sample_count").?.integer);
    const dirty = root.get("metrics").?.object.get("private_dirty").?.object;
    try std.testing.expectEqual(@as(i64, 900), dirty.get("peak").?.integer);
    try std.testing.expectEqual(@as(i64, 500), dirty.get("median").?.integer);
    try std.testing.expect(root.get("metrics").?.object.get("pss") == null);
    const series = root.get("samples").?.array;
    try std.testing.expectEqual(@as(usize, 2), series.items.len);
    try std.testing.expectEqual(@as(i64, 3000), series.items[1].object.get("rss").?.integer);
}
