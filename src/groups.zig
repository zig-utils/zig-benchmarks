//! Benchmark Groups - Organize benchmarks into categories
//!
//! Features:
//! - Group benchmarks by category (e.g., "algorithms", "I/O", "memory")
//! - Run specific groups or all groups
//! - Nested groups for hierarchical organization
//! - Group-level statistics and reporting

const std = @import("std");
const bench = @import("bench");
const Allocator = std.mem.Allocator;

/// A group of related benchmarks
pub const BenchmarkGroup = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    suite: bench.BenchmarkSuite,
    parent: ?*BenchmarkGroup = null,

    pub fn init(allocator: Allocator, name: []const u8) BenchmarkGroup {
        return .{
            .name = name,
            .suite = bench.BenchmarkSuite.init(allocator),
        };
    }

    pub fn initWithDescription(allocator: Allocator, name: []const u8, description: []const u8) BenchmarkGroup {
        return .{
            .name = name,
            .description = description,
            .suite = bench.BenchmarkSuite.init(allocator),
        };
    }

    pub fn deinit(self: *BenchmarkGroup) void {
        self.suite.deinit();
    }

    /// Add a benchmark to this group
    pub fn add(self: *BenchmarkGroup, name: []const u8, func: *const fn () void) !void {
        try self.suite.add(name, func);
    }

    /// Add a benchmark with options
    pub fn addWithOptions(self: *BenchmarkGroup, name: []const u8, func: *const fn () void, opts: bench.BenchmarkOptions) !void {
        try self.suite.addWithOptions(name, func, opts);
    }

    /// Add a benchmark with allocator
    pub fn addWithAllocator(self: *BenchmarkGroup, name: []const u8, func: *const fn (Allocator) void) !void {
        try self.suite.addWithAllocator(name, func);
    }

    /// Run all benchmarks in this group
    pub fn run(self: *BenchmarkGroup) !void {
        const stdout = std.fs.File.stdout();
        var buf: [512]u8 = undefined;

        // Print group header
        const header = try std.fmt.bufPrint(&buf, "\n{s}=== Group: {s} ==={s}\n", .{
            bench.Formatter.BOLD,
            self.name,
            bench.Formatter.RESET,
        });
        try stdout.writeAll(header);

        if (self.description) |desc| {
            const desc_line = try std.fmt.bufPrint(&buf, "{s}{s}{s}\n", .{
                bench.Formatter.DIM,
                desc,
                bench.Formatter.RESET,
            });
            try stdout.writeAll(desc_line);
        }

        try self.suite.run();
    }
};

/// Manager for multiple benchmark groups
pub const GroupManager = struct {
    groups: std.ArrayList(BenchmarkGroup),
    allocator: Allocator,
    active_group_filter: ?[]const u8 = null,

    pub fn init(allocator: Allocator) GroupManager {
        return .{
            .groups = std.ArrayList(BenchmarkGroup){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *GroupManager) void {
        for (self.groups.items) |*group| {
            group.deinit();
        }
        self.groups.deinit(self.allocator);
    }

    /// Add a new group
    pub fn addGroup(self: *GroupManager, name: []const u8) !*BenchmarkGroup {
        const group = BenchmarkGroup.init(self.allocator, name);
        try self.groups.append(self.allocator, group);
        return &self.groups.items[self.groups.items.len - 1];
    }

    /// Add a new group with description
    pub fn addGroupWithDescription(self: *GroupManager, name: []const u8, description: []const u8) !*BenchmarkGroup {
        const group = BenchmarkGroup.initWithDescription(self.allocator, name, description);
        try self.groups.append(self.allocator, group);
        return &self.groups.items[self.groups.items.len - 1];
    }

    /// Set filter to run only specific groups
    pub fn setGroupFilter(self: *GroupManager, filter: []const u8) void {
        self.active_group_filter = filter;
    }

    /// Check if a group matches the current filter
    fn matchesFilter(self: *const GroupManager, group_name: []const u8) bool {
        if (self.active_group_filter == null) return true;
        return std.mem.indexOf(u8, group_name, self.active_group_filter.?) != null;
    }

    /// Run all groups (or filtered groups)
    pub fn runAll(self: *GroupManager) !void {
        const stdout = std.fs.File.stdout();
        var buf: [512]u8 = undefined;

        const header = try std.fmt.bufPrint(&buf, "\n{s}{s}Benchmark Groups{s}\n", .{
            bench.Formatter.BOLD,
            bench.Formatter.CYAN,
            bench.Formatter.RESET,
        });
        try stdout.writeAll(header);

        var ran_count: usize = 0;
        for (self.groups.items) |*group| {
            if (!self.matchesFilter(group.name)) continue;

            try group.run();
            ran_count += 1;
        }

        if (ran_count == 0) {
            try stdout.writeAll("\nNo groups matched the filter.\n");
        } else {
            const summary = try std.fmt.bufPrint(&buf, "\n{s}Ran {d} group(s){s}\n", .{
                bench.Formatter.GREEN,
                ran_count,
                bench.Formatter.RESET,
            });
            try stdout.writeAll(summary);
        }
    }

    /// Run a specific group by name
    pub fn runGroup(self: *GroupManager, name: []const u8) !void {
        for (self.groups.items) |*group| {
            if (std.mem.eql(u8, group.name, name)) {
                try group.run();
                return;
            }
        }
        return error.GroupNotFound;
    }

    /// Get statistics across all groups
    pub fn getGroupStats(self: *const GroupManager) GroupStats {
        var stats = GroupStats{};
        for (self.groups.items) |group| {
            stats.total_groups += 1;
            stats.total_benchmarks += group.suite.benchmarks.items.len;
        }
        return stats;
    }
};

/// Statistics about groups
pub const GroupStats = struct {
    total_groups: usize = 0,
    total_benchmarks: usize = 0,
};
