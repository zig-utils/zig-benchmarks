const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create a module for the benchmark library
    const bench_module = b.createModule(.{
        .root_source_file = b.path("src/bench.zig"),
    });

    // Example executables
    const examples = [_]struct {
        name: []const u8,
        path: []const u8,
    }{
        .{ .name = "basic", .path = "examples/basic.zig" },
        .{ .name = "async", .path = "examples/async.zig" },
        .{ .name = "custom_options", .path = "examples/custom_options.zig" },
    };

    inline for (examples) |example| {
        const exe_module = b.createModule(.{
            .root_source_file = b.path(example.path),
            .target = target,
            .optimize = optimize,
        });
        exe_module.addImport("bench", bench_module);

        const exe = b.addExecutable(.{
            .name = example.name,
            .root_module = exe_module,
        });

        const install_exe = b.addInstallArtifact(exe, .{});

        const exe_step = b.step(example.name, b.fmt("Build {s} example", .{example.name}));
        exe_step.dependOn(&install_exe.step);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(&install_exe.step);

        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step(b.fmt("run-{s}", .{example.name}), b.fmt("Run the {s} example", .{example.name}));
        run_step.dependOn(&run_cmd.step);
    }

    // Default step builds all examples
    const all_step = b.step("examples", "Build all examples");
    inline for (examples) |example| {
        const exe_module = b.createModule(.{
            .root_source_file = b.path(example.path),
            .target = target,
            .optimize = optimize,
        });
        exe_module.addImport("bench", bench_module);

        const exe = b.addExecutable(.{
            .name = example.name,
            .root_module = exe_module,
        });

        const install_exe = b.addInstallArtifact(exe, .{});
        all_step.dependOn(&install_exe.step);
    }

    // Unit tests
    const test_module = b.createModule(.{
        .root_source_file = b.path("src/bench.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.addTest(.{
        .root_module = test_module,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
