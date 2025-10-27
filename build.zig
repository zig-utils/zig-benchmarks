const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create a module for the benchmark library
    const bench_module = b.createModule(.{
        .root_source_file = b.path("src/bench.zig"),
    });

    // Create modules for advanced features
    const export_module = b.createModule(.{
        .root_source_file = b.path("src/export.zig"),
    });
    export_module.addImport("bench", bench_module);

    const comparison_module = b.createModule(.{
        .root_source_file = b.path("src/comparison.zig"),
    });
    comparison_module.addImport("bench", bench_module);

    const memory_profiler_module = b.createModule(.{
        .root_source_file = b.path("src/memory_profiler.zig"),
    });

    const ci_module = b.createModule(.{
        .root_source_file = b.path("src/ci.zig"),
    });
    ci_module.addImport("bench", bench_module);
    ci_module.addImport("comparison", comparison_module);

    const flamegraph_module = b.createModule(.{
        .root_source_file = b.path("src/flamegraph.zig"),
    });

    // Advanced Features - Phase 2 modules
    const groups_module = b.createModule(.{
        .root_source_file = b.path("src/groups.zig"),
    });
    groups_module.addImport("bench", bench_module);

    const warmup_module = b.createModule(.{
        .root_source_file = b.path("src/warmup.zig"),
    });
    warmup_module.addImport("bench", bench_module);

    const outliers_module = b.createModule(.{
        .root_source_file = b.path("src/outliers.zig"),
    });
    outliers_module.addImport("bench", bench_module);

    const parameterized_module = b.createModule(.{
        .root_source_file = b.path("src/parameterized.zig"),
    });
    parameterized_module.addImport("bench", bench_module);

    const parallel_module = b.createModule(.{
        .root_source_file = b.path("src/parallel.zig"),
    });
    parallel_module.addImport("bench", bench_module);

    // Example executables
    const examples = [_]struct {
        name: []const u8,
        path: []const u8,
    }{
        .{ .name = "basic", .path = "examples/basic.zig" },
        .{ .name = "async", .path = "examples/async.zig" },
        .{ .name = "custom_options", .path = "examples/custom_options.zig" },
        .{ .name = "filtering_baseline", .path = "examples/filtering_baseline.zig" },
        .{ .name = "allocators", .path = "examples/allocators.zig" },
        .{ .name = "advanced_features", .path = "examples/advanced_features.zig" },
        .{ .name = "phase2_features", .path = "examples/phase2_features.zig" },
    };

    inline for (examples) |example| {
        const exe_module = b.createModule(.{
            .root_source_file = b.path(example.path),
            .target = target,
            .optimize = optimize,
        });
        exe_module.addImport("bench", bench_module);

        // Add advanced feature imports for advanced_features example
        if (std.mem.eql(u8, example.name, "advanced_features")) {
            exe_module.addImport("export", export_module);
            exe_module.addImport("comparison", comparison_module);
            exe_module.addImport("memory_profiler", memory_profiler_module);
            exe_module.addImport("ci", ci_module);
            exe_module.addImport("flamegraph", flamegraph_module);
        }

        // Add Phase 2 feature imports for phase2_features example
        if (std.mem.eql(u8, example.name, "phase2_features")) {
            exe_module.addImport("groups", groups_module);
            exe_module.addImport("warmup", warmup_module);
            exe_module.addImport("outliers", outliers_module);
            exe_module.addImport("parameterized", parameterized_module);
            exe_module.addImport("parallel", parallel_module);
        }

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

        // Add advanced feature imports for advanced_features example
        if (std.mem.eql(u8, example.name, "advanced_features")) {
            exe_module.addImport("export", export_module);
            exe_module.addImport("comparison", comparison_module);
            exe_module.addImport("memory_profiler", memory_profiler_module);
            exe_module.addImport("ci", ci_module);
            exe_module.addImport("flamegraph", flamegraph_module);
        }

        // Add Phase 2 feature imports for phase2_features example
        if (std.mem.eql(u8, example.name, "phase2_features")) {
            exe_module.addImport("groups", groups_module);
            exe_module.addImport("warmup", warmup_module);
            exe_module.addImport("outliers", outliers_module);
            exe_module.addImport("parameterized", parameterized_module);
            exe_module.addImport("parallel", parallel_module);
        }

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

    const unit_tests = b.addTest(.{
        .root_module = test_module,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Integration tests
    const integration_test_module = b.createModule(.{
        .root_source_file = b.path("tests/integration_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    integration_test_module.addImport("bench", bench_module);

    const integration_tests = b.addTest(.{
        .root_module = integration_test_module,
    });

    const run_integration_tests = b.addRunArtifact(integration_tests);

    // Test steps
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_integration_tests.step);

    const unit_test_step = b.step("test-unit", "Run unit tests only");
    unit_test_step.dependOn(&run_unit_tests.step);

    const integration_test_step = b.step("test-integration", "Run integration tests only");
    integration_test_step.dependOn(&run_integration_tests.step);
}
