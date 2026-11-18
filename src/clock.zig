//! Clock helpers built on `std.Io` clocks.
//!
//! Zig 0.17 removed `std.time.Timer` and the global `std.time.*Timestamp`
//! functions; every clock read now goes through an `std.Io` instance. This
//! module provides the stopwatch and wall-clock reads the framework needs,
//! taking the `io` explicitly.

const std = @import("std");
const Io = std.Io;

/// Monotonic stopwatch over the `.awake` clock.
///
/// Readings are nanoseconds since `start` (or the last `reset`/`lap`).
pub const Timer = struct {
    io: Io,
    started: Io.Timestamp,

    /// Start a new timer.
    pub fn start(io: Io) Timer {
        return .{ .io = io, .started = Io.Clock.awake.now(io) };
    }

    /// Nanoseconds elapsed since the timer was started or last reset.
    pub fn read(self: *const Timer) u64 {
        return elapsedNs(self.started, Io.Clock.awake.now(self.io));
    }

    /// Restart the timer from now.
    pub fn reset(self: *Timer) void {
        self.started = Io.Clock.awake.now(self.io);
    }

    /// Return the elapsed nanoseconds and restart the timer.
    pub fn lap(self: *Timer) u64 {
        const now = Io.Clock.awake.now(self.io);
        defer self.started = now;
        return elapsedNs(self.started, now);
    }
};

fn elapsedNs(from: Io.Timestamp, to: Io.Timestamp) u64 {
    const ns = from.durationTo(to).nanoseconds;
    if (ns <= 0) return 0;
    return std.math.cast(u64, ns) orelse std.math.maxInt(u64);
}

/// Wall-clock time in nanoseconds since the Unix epoch.
pub fn nanoTimestamp(io: Io) i96 {
    return Io.Clock.real.now(io).toNanoseconds();
}

/// Wall-clock time in milliseconds since the Unix epoch.
pub fn milliTimestamp(io: Io) i64 {
    return Io.Clock.real.now(io).toMilliseconds();
}

/// Wall-clock time in seconds since the Unix epoch.
pub fn timestamp(io: Io) i64 {
    return Io.Clock.real.now(io).toSeconds();
}

test "Timer - read is monotonic and reset restarts" {
    const io = std.testing.io;
    var timer = Timer.start(io);
    const first = timer.read();
    const second = timer.read();
    try std.testing.expect(second >= first);

    timer.reset();
    _ = timer.lap();
    try std.testing.expect(timer.read() < std.time.ns_per_s);
}

test "wall-clock helpers agree on units" {
    const io = std.testing.io;
    const s = timestamp(io);
    const ms = milliTimestamp(io);
    try std.testing.expect(s > 0);
    try std.testing.expect(@divTrunc(ms, 1000) >= s);
}
