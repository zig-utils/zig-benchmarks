//! Parameterized Benchmarks - Run benchmarks with different parameters
//!
//! Features:
//! - Test functions with multiple input sizes
//! - Compare performance across different parameters
//! - Type-safe parameter passing
//! - Automatic naming with parameter values

const std = @import("std");
const bench = @import("bench");
const Allocator = std.mem.Allocator;

/// A parameterized benchmark that runs with different input values
pub fn ParameterizedBenchmark(comptime T: type) type {
    return struct {
        const Self = @This();

        name_template: []const u8,
        func: *const fn (T) void,
        parameters: []const T,
        opts: bench.BenchmarkOptions,
        allocator: Allocator,

        /// Initialize a parameterized benchmark
        pub fn init(
            allocator: Allocator,
            name_template: []const u8,
            func: *const fn (T) void,
            parameters: []const T,
        ) Self {
            return .{
                .name_template = name_template,
                .func = func,
                .parameters = parameters,
                .opts = .{},
                .allocator = allocator,
            };
        }

        /// Initialize with custom options
        pub fn initWithOptions(
            allocator: Allocator,
            name_template: []const u8,
            func: *const fn (T) void,
            parameters: []const T,
            opts: bench.BenchmarkOptions,
        ) Self {
            return .{
                .name_template = name_template,
                .func = func,
                .parameters = parameters,
                .opts = opts,
                .allocator = allocator,
            };
        }

        /// Generate benchmark suite with all parameters
        pub fn generateSuite(self: *const Self) !bench.BenchmarkSuite {
            var suite = bench.BenchmarkSuite.init(self.allocator);

            for (self.parameters) |param| {
                // Create wrapper function for this parameter
                const wrapper = struct {
                    var global_param: T = undefined;
                    var global_func: *const fn (T) void = undefined;

                    fn wrapperFunc() void {
                        global_func(global_param);
                    }
                };

                wrapper.global_param = param;
                wrapper.global_func = self.func;

                // Generate name with parameter value
                const param_name = try self.formatParameterName(param);
                defer self.allocator.free(param_name);

                var name_buf: [256]u8 = undefined;
                const full_name = try std.fmt.bufPrint(&name_buf, "{s} [{s}]", .{ self.name_template, param_name });
                const owned_name = try self.allocator.dupe(u8, full_name);

                try suite.addWithOptions(owned_name, wrapper.wrapperFunc, self.opts);
            }

            return suite;
        }

        /// Format parameter value for display
        fn formatParameterName(self: *const Self, param: T) ![]u8 {
            var buf: [128]u8 = undefined;
            const formatted = switch (@typeInfo(T)) {
                .Int => try std.fmt.bufPrint(&buf, "{d}", .{param}),
                .Float => try std.fmt.bufPrint(&buf, "{d:.2}", .{param}),
                .Pointer => |ptr_info| {
                    if (ptr_info.child == u8) {
                        // String parameter
                        const str: []const u8 = @ptrCast(param);
                        try std.fmt.bufPrint(&buf, "{s}", .{str})
                    } else {
                        try std.fmt.bufPrint(&buf, "ptr", .{})
                    }
                },
                else => try std.fmt.bufPrint(&buf, "param", .{}),
            };
            return try self.allocator.dupe(u8, formatted);
        }
    };
}

/// Helper to create parameterized benchmarks with integer parameters
pub fn intParameterized(
    allocator: Allocator,
    name: []const u8,
    func: *const fn (i64) void,
    parameters: []const i64,
) !bench.BenchmarkSuite {
    const pb = ParameterizedBenchmark(i64).init(allocator, name, func, parameters);
    return try pb.generateSuite();
}

/// Helper to create parameterized benchmarks with size parameters (common use case)
pub fn sizeParameterized(
    allocator: Allocator,
    name: []const u8,
    func: *const fn (usize) void,
    sizes: []const usize,
) !bench.BenchmarkSuite {
    const pb = ParameterizedBenchmark(usize).init(allocator, name, func, sizes);
    return try pb.generateSuite();
}

/// Parameterized benchmark with allocator
pub fn ParameterizedBenchmarkWithAllocator(comptime T: type) type {
    return struct {
        const Self = @This();

        name_template: []const u8,
        func: *const fn (Allocator, T) void,
        parameters: []const T,
        opts: bench.BenchmarkOptions,
        allocator: Allocator,

        pub fn init(
            allocator: Allocator,
            name_template: []const u8,
            func: *const fn (Allocator, T) void,
            parameters: []const T,
        ) Self {
            return .{
                .name_template = name_template,
                .func = func,
                .parameters = parameters,
                .opts = .{},
                .allocator = allocator,
            };
        }

        pub fn generateSuite(self: *const Self) !bench.BenchmarkSuite {
            var suite = bench.BenchmarkSuite.init(self.allocator);

            for (self.parameters) |param| {
                const wrapper = struct {
                    var global_param: T = undefined;
                    var global_func: *const fn (Allocator, T) void = undefined;
                    var global_allocator: Allocator = undefined;

                    fn wrapperFunc(alloc: Allocator) void {
                        global_func(alloc, global_param);
                    }
                };

                wrapper.global_param = param;
                wrapper.global_func = self.func;
                wrapper.global_allocator = self.allocator;

                // Generate name with parameter value
                const param_name = try formatParam(T, param, self.allocator);
                defer self.allocator.free(param_name);

                var name_buf: [256]u8 = undefined;
                const full_name = try std.fmt.bufPrint(&name_buf, "{s} [{s}]", .{ self.name_template, param_name });
                const owned_name = try self.allocator.dupe(u8, full_name);

                try suite.addWithAllocator(owned_name, wrapper.wrapperFunc);
            }

            return suite;
        }
    };
}

/// Format a parameter for display
fn formatParam(comptime T: type, param: T, allocator: Allocator) ![]u8 {
    var buf: [128]u8 = undefined;
    const formatted = switch (@typeInfo(T)) {
        .Int => try std.fmt.bufPrint(&buf, "{d}", .{param}),
        .Float => try std.fmt.bufPrint(&buf, "{d:.2}", .{param}),
        else => try std.fmt.bufPrint(&buf, "param", .{}),
    };
    return try allocator.dupe(u8, formatted);
}
