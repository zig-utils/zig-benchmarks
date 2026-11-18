//! Acceptance tests for the external-process benchmark mode. They run
//! `process_child` (tests/process_child.zig) and check what the sampler saw.

const std = @import("std");
const process = @import("process");
const options = @import("process_test_options");

const testing = std.testing;
const mib = 1024 * 1024;

fn tmpPath(buf: []u8, tmp: *const testing.TmpDir, name: []const u8) ![]const u8 {
    return std.fmt.bufPrint(buf, ".zig-cache/tmp/{s}/{s}", .{ tmp.sub_path, name });
}

test "allocating and touching 64 MiB in a child reports about 64 MiB private dirty" {
    if (!process.supported) return error.SkipZigTest;
    var result = try process.run(testing.allocator, testing.io, .{
        .argv = &.{ options.child_path, "dirty", "64", "600" },
        .sample_hz = 50,
    });
    defer result.deinit();

    try testing.expect(result.term.success());
    const dirty = result.summary(.private_dirty).?;
    try testing.expect(dirty.peak() >= 60 * mib);
    try testing.expect(dirty.peak() <= 80 * mib);
    // Written anonymous memory is never clean.
    try testing.expect(result.stat(.private_clean, .peak).? < 16 * mib);
    try testing.expect(result.samples.len >= 5);
    try testing.expect(result.wall_ns >= 600 * std.time.ns_per_ms);
    try testing.expect(result.minor_faults.? > 0);

    try result.enforce(&.{.{ .metric = .private_dirty, .max_bytes = 80 * mib }}, null);
    try testing.expectError(
        error.GateExceeded,
        result.enforce(&.{.{ .metric = .private_dirty, .max_bytes = 32 * mib }}, null),
    );
}

test "mmapping and reading a 64 MiB file reports it as clean, not dirty" {
    if (!process.supported) return error.SkipZigTest;
    const io = testing.io;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    {
        const file = try tmp.dir.createFile(io, "data.bin", .{});
        defer file.close(io);
        var chunk: [64 * 1024]u8 = undefined;
        for (&chunk, 0..) |*b, i| b.* = @truncate(i *% 131 +% 7);
        var written: usize = 0;
        while (written < 64 * mib) : (written += chunk.len) {
            try file.writePositionalAll(io, &chunk, written);
        }
        // Write the pages back: a page still dirty in the page cache is counted as
        // dirty by smaps even when the reader never writes to it.
        try file.sync(io);
    }

    var path_buf: [128]u8 = undefined;
    const path = try tmpPath(&path_buf, &tmp, "data.bin");
    var result = try process.run(testing.allocator, io, .{
        .argv = &.{ options.child_path, "mapfile", path, "600" },
        .sample_hz = 50,
    });
    defer result.deinit();

    try testing.expect(result.term.success());
    try testing.expect(result.stat(.private_clean, .peak).? >= 60 * mib);
    try testing.expect(result.stat(.private_dirty, .peak).? < 16 * mib);
}

test "stdin driver feeds the child and closes its stdin" {
    if (!process.supported) return error.SkipZigTest;
    const payload = try testing.allocator.alloc(u8, 300_000);
    defer testing.allocator.free(payload);
    @memset(payload, 'x');

    var result = try process.run(testing.allocator, testing.io, .{
        .argv = &.{ options.child_path, "stdin", "300000" },
        .driver = .{ .stdin_bytes = payload },
    });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u64, 300_000), result.driver.bytes_written);
}

test "unix socket driver connects once the child listens" {
    if (!process.supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [128]u8 = undefined;
    const path = try tmpPath(&path_buf, &tmp, "s.sock");

    const request: [5000]u8 = @splat('a');
    var result = try process.run(testing.allocator, testing.io, .{
        .argv = &.{ options.child_path, "socket", path, "5000" },
        .driver = .{ .unix_socket = .{ .path = path, .request = &request } },
    });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u64, 5000), result.driver.bytes_written);
    try testing.expectEqual(@as(u64, 2), result.driver.bytes_read);
}

test "timeout kills the child" {
    if (!process.supported) return error.SkipZigTest;
    var result = try process.run(testing.allocator, testing.io, .{
        .argv = &.{ options.child_path, "dirty", "1", "30000" },
        .timeout_ns = 200 * std.time.ns_per_ms,
    });
    defer result.deinit();

    try testing.expect(result.timed_out);
    try testing.expectEqual(std.process.Child.Term{ .signal = .KILL }, result.term);
    try testing.expect(result.wall_ns < 10 * std.time.ns_per_s);
}

test "JSON result carries peak, median and the series" {
    if (!process.supported) return error.SkipZigTest;
    var result = try process.run(testing.allocator, testing.io, .{
        .argv = &.{ options.child_path, "dirty", "8", "300" },
        .sample_hz = 20,
    });
    defer result.deinit();

    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try result.writeJson(&out.writer);

    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, out.written(), .{});
    defer parsed.deinit();
    const dirty = parsed.value.object.get("metrics").?.object.get("private_dirty").?.object;
    try testing.expect(dirty.get("peak").?.integer >= 8 * mib);
    try testing.expect(dirty.get("median").?.integer > 0);
    try testing.expectEqual(result.samples.len, parsed.value.object.get("samples").?.array.items.len);
}
