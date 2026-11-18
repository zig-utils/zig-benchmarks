const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Public modules: dependents import them by these names (`bench`, `exporters`, ...).
    const bench_module = b.addModule("bench", .{
        .root_source_file = b.path("src/bench.zig"),
    });

    // Create modules for advanced features
    const export_module = b.addModule("export", .{
        .root_source_file = b.path("src/export.zig"),
    });
    export_module.addImport("bench", bench_module);

    const comparison_module = b.addModule("comparison", .{
        .root_source_file = b.path("src/comparison.zig"),
    });
    comparison_module.addImport("bench", bench_module);

    const memory_profiler_module = b.addModule("memory_profiler", .{
        .root_source_file = b.path("src/memory_profiler.zig"),
    });

    const ci_module = b.addModule("ci", .{
        .root_source_file = b.path("src/ci.zig"),
    });
    ci_module.addImport("bench", bench_module);
    ci_module.addImport("comparison", comparison_module);

    const flamegraph_module = b.addModule("flamegraph", .{
        .root_source_file = b.path("src/flamegraph.zig"),
    });

    // Advanced Features - Phase 2 modules
    const groups_module = b.addModule("groups", .{
        .root_source_file = b.path("src/groups.zig"),
    });
    groups_module.addImport("bench", bench_module);

    const warmup_module = b.addModule("warmup", .{
        .root_source_file = b.path("src/warmup.zig"),
    });
    warmup_module.addImport("bench", bench_module);

    const outliers_module = b.addModule("outliers", .{
        .root_source_file = b.path("src/outliers.zig"),
    });
    outliers_module.addImport("bench", bench_module);

    const parameterized_module = b.addModule("parameterized", .{
        .root_source_file = b.path("src/parameterized.zig"),
    });
    parameterized_module.addImport("bench", bench_module);

    const parallel_module = b.addModule("parallel", .{
        .root_source_file = b.path("src/parallel.zig"),
    });
    parallel_module.addImport("bench", bench_module);

    // Advanced Features - Phase 3 modules
    const streaming_module = b.addModule("streaming", .{
        .root_source_file = b.path("src/streaming.zig"),
    });
    streaming_module.addImport("bench", bench_module);

    const ab_testing_module = b.addModule("ab_testing", .{
        .root_source_file = b.path("src/ab_testing.zig"),
    });
    ab_testing_module.addImport("bench", bench_module);

    const diff_module = b.addModule("diff", .{
        .root_source_file = b.path("src/diff.zig"),
    });
    diff_module.addImport("bench", bench_module);

    const monitoring_module = b.addModule("monitoring", .{
        .root_source_file = b.path("src/monitoring.zig"),
    });
    monitoring_module.addImport("bench", bench_module);

    const exporters_module = b.addModule("exporters", .{
        .root_source_file = b.path("src/exporters.zig"),
    });
    exporters_module.addImport("bench", bench_module);

    const profiling_module = b.addModule("profiling", .{
        .root_source_file = b.path("src/profiling.zig"),
    });
    profiling_module.addImport("bench", bench_module);

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
        .{ .name = "phase3_features", .path = "examples/phase3_features.zig" },
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

        // Add Phase 3 feature imports for phase3_features example
        if (std.mem.eql(u8, example.name, "phase3_features")) {
            exe_module.addImport("streaming", streaming_module);
            exe_module.addImport("ab_testing", ab_testing_module);
            exe_module.addImport("diff", diff_module);
            exe_module.addImport("monitoring", monitoring_module);
            exe_module.addImport("exporters", exporters_module);
            exe_module.addImport("profiling", profiling_module);
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

        run_cmd.addPassthruArgs();

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

        // Add Phase 3 feature imports for phase3_features example
        if (std.mem.eql(u8, example.name, "phase3_features")) {
            exe_module.addImport("streaming", streaming_module);
            exe_module.addImport("ab_testing", ab_testing_module);
            exe_module.addImport("diff", diff_module);
            exe_module.addImport("monitoring", monitoring_module);
            exe_module.addImport("exporters", exporters_module);
            exe_module.addImport("profiling", profiling_module);
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

    // Test steps: bench.zig, the integration tests, and every other module's own tests.
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_unit_tests.step);
    for ([_]*std.Build.Module{
        export_module,        comparison_module, memory_profiler_module, ci_module,
        flamegraph_module,    groups_module,     warmup_module,          outliers_module,
        parameterized_module, parallel_module,   streaming_module,       ab_testing_module,
        diff_module,          monitoring_module, exporters_module,       profiling_module,
    }) |module| {
        // Library modules carry no target, so test a copy that has one and the same imports.
        const test_mod = b.createModule(.{
            .root_source_file = module.root_source_file,
            .target = target,
            .optimize = optimize,
        });
        for (module.import_table.keys(), module.import_table.values()) |import_name, imported| {
            test_mod.addImport(import_name, imported);
        }
        test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = test_mod })).step);
    }
    test_step.dependOn(&run_integration_tests.step);

    const unit_test_step = b.step("test-unit", "Run unit tests only");
    unit_test_step.dependOn(&run_unit_tests.step);

    const integration_test_step = b.step("test-integration", "Run integration tests only");
    integration_test_step.dependOn(&run_integration_tests.step);
}
