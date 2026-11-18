//! Child program for the external-process benchmark tests.
//!
//!   dirty <mib> <hold_ms>        allocate and write <mib> MiB, then hold it
//!   mapfile <path> <hold_ms>     mmap <path> read-only, read every page, then hold
//!   stdin <expect_bytes>         read stdin to EOF; exit 0 if the count matches
//!   socket <path> <expect_bytes> serve one Unix socket connection: read to EOF,
//!                                reply "ok", exit 0 if the count matches

const std = @import("std");
const Io = std.Io;

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) return 2;
    const mode = args[1];

    if (std.mem.eql(u8, mode, "dirty")) {
        const mib = try std.fmt.parseInt(usize, args[2], 10);
        const hold_ms = try std.fmt.parseInt(i64, args[3], 10);
        const len = mib * 1024 * 1024;
        const memory = try std.heap.page_allocator.alloc(u8, len);
        defer std.heap.page_allocator.free(memory);
        // A non-repeating pattern so neither zero-page dedup nor compression shrinks it.
        var x: u32 = 0x9e3779b9;
        for (memory) |*byte| {
            x ^= x << 13;
            x ^= x >> 17;
            x ^= x << 5;
            byte.* = @truncate(x);
        }
        std.mem.doNotOptimizeAway(memory.ptr);
        try io.sleep(.fromMilliseconds(hold_ms), .awake);
        return 0;
    }

    if (std.mem.eql(u8, mode, "mapfile")) {
        const hold_ms = try std.fmt.parseInt(i64, args[3], 10);
        const file = try Io.Dir.cwd().openFile(io, args[2], .{});
        defer file.close(io);
        const len: usize = @intCast(try file.length(io));
        const memory = try std.posix.mmap(null, len, .{ .READ = true }, .{ .TYPE = .PRIVATE }, file.handle, 0);
        defer std.posix.munmap(memory);
        var sum: u64 = 0;
        const page = std.heap.pageSize();
        var i: usize = 0;
        while (i < len) : (i += page) sum +%= @as(*volatile u8, @ptrCast(&memory[i])).*;
        std.mem.doNotOptimizeAway(sum);
        try io.sleep(.fromMilliseconds(hold_ms), .awake);
        return 0;
    }

    if (std.mem.eql(u8, mode, "stdin")) {
        const expect = try std.fmt.parseInt(u64, args[2], 10);
        var buf: [4096]u8 = undefined;
        var reader = Io.File.stdin().readerStreaming(io, &buf);
        const got = try countRemaining(&reader.interface);
        return if (got == expect) 0 else 1;
    }

    if (std.mem.eql(u8, mode, "socket")) {
        const expect = try std.fmt.parseInt(u64, args[3], 10);
        const address = try Io.net.UnixAddress.init(args[2]);
        var server = try address.listen(io, .{});
        defer server.deinit(io);
        const stream = try server.accept(io);
        defer stream.close(io);
        var rbuf: [4096]u8 = undefined;
        var reader = stream.reader(io, &rbuf);
        const got = try countRemaining(&reader.interface);
        var wbuf: [64]u8 = undefined;
        var writer = stream.writer(io, &wbuf);
        try writer.interface.writeAll("ok");
        try writer.interface.flush();
        return if (got == expect) 0 else 1;
    }

    return 2;
}

/// Count the bytes left in `reader`. (Not `discardRemaining`: in Zig 0.17.0-dev.1857
/// a streaming File.Reader drops the bytes still buffered when it hits end of
/// stream, so the count comes up short.)
fn countRemaining(reader: *Io.Reader) !u64 {
    var buf: [4096]u8 = undefined;
    var total: u64 = 0;
    while (true) {
        const n = try reader.readSliceShort(&buf);
        total += n;
        if (n < buf.len) return total;
    }
}
