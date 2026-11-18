//! procbench: run a command and report its memory and CPU use.
//!
//!   procbench [options] -- <command> [args...]
//!
//!   --hz <n>              samples per second (default 10)
//!   --stdin <file>        stream <file> to the command's stdin
//!   --socket <path>       connect to a Unix socket the command listens on
//!   --request <file>      bytes to send over --socket (default: nothing)
//!   --timeout-ms <n>      kill the command after <n> ms
//!   --json <file>         write the JSON result to <file> ("-" for stdout)
//!   --max-dirty-mib <n>   gate: fail if peak private dirty exceeds <n> MiB
//!   --max-rss-mib <n>     gate: fail if peak RSS exceeds <n> MiB
//!   --max-pss-mib <n>     gate: fail if peak PSS exceeds <n> MiB (Linux)
//!
//! Exit status: 0 on success, 1 if the command failed, 3 if a gate failed.

const std = @import("std");
const process = @import("process");

const mib = 1024 * 1024;

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buf);
    const out = &stdout_writer.interface;
    defer out.flush() catch {};

    var options: process.Options = .{ .argv = &.{} };
    var json_path: ?[]const u8 = null;
    var socket_path: ?[]const u8 = null;
    var request: []const u8 = "";
    var gates: std.ArrayList(process.Gate) = .empty;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--")) {
            options.argv = args[i + 1 ..];
            break;
        }
        if (i + 1 >= args.len) return usage(out);
        const value = args[i + 1];
        i += 1;
        if (std.mem.eql(u8, arg, "--hz")) {
            options.sample_hz = try std.fmt.parseInt(u32, value, 10);
        } else if (std.mem.eql(u8, arg, "--stdin")) {
            options.driver = .{ .stdin_file = value };
        } else if (std.mem.eql(u8, arg, "--socket")) {
            socket_path = value;
        } else if (std.mem.eql(u8, arg, "--request")) {
            request = try std.Io.Dir.cwd().readFileAlloc(io, value, arena, .unlimited);
        } else if (std.mem.eql(u8, arg, "--timeout-ms")) {
            options.timeout_ns = try std.fmt.parseInt(u64, value, 10) * std.time.ns_per_ms;
        } else if (std.mem.eql(u8, arg, "--json")) {
            json_path = value;
        } else if (std.mem.eql(u8, arg, "--max-dirty-mib")) {
            try gates.append(arena, .{ .metric = .private_dirty, .max_bytes = try parseMib(value) });
        } else if (std.mem.eql(u8, arg, "--max-rss-mib")) {
            try gates.append(arena, .{ .metric = .rss, .max_bytes = try parseMib(value) });
        } else if (std.mem.eql(u8, arg, "--max-pss-mib")) {
            try gates.append(arena, .{ .metric = .pss, .max_bytes = try parseMib(value) });
        } else return usage(out);
    }
    if (options.argv.len == 0) return usage(out);
    if (socket_path) |path| options.driver = .{ .unix_socket = .{ .path = path, .request = request } };

    var result = try process.run(init.gpa, io, options);
    defer result.deinit();

    try out.print("{s}: {f} in {d:.1} ms", .{ options.argv[0], result.term, nsToMs(result.wall_ns) });
    if (result.user_cpu_ns) |user| try out.print(", user {d:.1} ms", .{nsToMs(user)});
    if (result.system_cpu_ns) |sys| try out.print(", sys {d:.1} ms", .{nsToMs(sys)});
    if (result.minor_faults) |f| try out.print(", {d} minor / {d} major faults", .{ f, result.major_faults orelse 0 });
    try out.print("\n{d} samples at {d} Hz\n", .{ result.samples.len, result.sample_hz });
    for (process.Metric.all) |metric| {
        const s = result.summary(metric) orelse continue;
        try out.print("  {s:<15} peak {d:>10.1} MiB  median {d:>10.1} MiB\n", .{
            @tagName(metric), bytesToMib(s.peak()), bytesToMib(s.median),
        });
    }

    if (json_path) |path| {
        if (std.mem.eql(u8, path, "-")) {
            try result.writeJson(out);
            try out.writeAll("\n");
        } else {
            const file = try std.Io.Dir.cwd().createFile(io, path, .{});
            defer file.close(io);
            var buf: [4096]u8 = undefined;
            var writer = file.writer(io, &buf);
            try result.writeJson(&writer.interface);
            try writer.interface.flush();
        }
    }

    result.enforce(gates.items, out) catch |err| switch (err) {
        error.GateExceeded, error.MetricUnavailable => return 3,
        else => return err,
    };
    return if (result.term.success()) 0 else 1;
}

fn parseMib(text: []const u8) !u64 {
    return try std.fmt.parseInt(u64, text, 10) * mib;
}

fn nsToMs(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / std.time.ns_per_ms;
}

fn bytesToMib(bytes: u64) f64 {
    return @as(f64, @floatFromInt(bytes)) / mib;
}

fn usage(out: *std.Io.Writer) u8 {
    out.writeAll("usage: procbench [--hz n] [--stdin file] [--socket path [--request file]]" ++
        " [--timeout-ms n] [--json file] [--max-dirty-mib n] [--max-rss-mib n] [--max-pss-mib n]" ++
        " -- command [args...]\n") catch {};
    return 2;
}
