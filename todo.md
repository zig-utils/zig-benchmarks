# Zig Benchmark Framework - TODO

## Core Implementation ✅
- [x] Design the benchmark framework API and architecture
- [x] Implement core benchmark runner with timing utilities
- [x] Implement statistical analysis (mean, stddev, percentiles)
- [x] Create pretty CLI output formatter with colors
- [x] Add support for async benchmarks
- [x] Test and verify builds successfully on Zig 0.15
- [x] Fix buffer overflow in formatTime/formatOps functions
- [x] Implement comparison and baseline features
- [x] Add support for custom allocators in benchmarks
- [x] Implement benchmark filtering (run specific benchmarks)

## Advanced Features ✅
- [x] JSON/CSV output export
- [x] Historical comparison (compare against saved baselines)
- [x] Memory profiling integration
- [x] Flamegraph generation support
- [x] CI/CD integration helpers
- [x] Regression detection

## Examples & Documentation ✅
- [x] Create example benchmarks demonstrating usage
- [x] Create basic.zig example
- [x] Create async.zig example
- [x] Create custom_options.zig example
- [x] Create filtering_baseline.zig example
- [x] Create allocators.zig example
- [x] Create advanced_features.zig example (demonstrates all 6 advanced features)
- [x] Write comprehensive README with documentation
- [x] Document advanced features in README
- [x] Add inline documentation to core modules

## Build & Testing
- [x] Create build.zig for the project
- [x] Add all examples to build system
- [x] Test all examples compile and run
- [x] Add unit tests for statistical functions (25+ tests)
- [x] Add integration tests for benchmark runner (16 tests)
- [x] Set up test commands (test, test-unit, test-integration)
- [ ] Test on different platforms (Linux, Windows)

## Advanced Features - Phase 2 ✅
- [x] Support for benchmark groups/categories (src/groups.zig)
- [x] Automatic warmup detection (src/warmup.zig)
- [x] Statistical outlier detection and removal (src/outliers.zig)
- [x] Support for parameterized benchmarks (src/parameterized.zig)
- [x] Multi-threaded benchmark support (src/parallel.zig)
- [x] GitHub Actions workflow template (.github/workflows/benchmarks.yml)
- [x] GitLab CI template (.gitlab-ci.yml)
- [x] Web dashboard for viewing benchmark history (web/dashboard.html)

## Documentation & Integration
- [ ] Update build.zig to include new modules
- [ ] Create comprehensive example demonstrating new features
- [ ] Update README with new features documentation
- [ ] Create user guide for advanced features

## Future Enhancements - Phase 3
- [ ] Real-time benchmark streaming
- [ ] Historical trend analysis with database backend
- [ ] A/B testing framework
- [ ] Benchmark result diff viewer
- [ ] Integration with monitoring systems (Prometheus, Grafana)
- [ ] Custom result exporters (XML, Markdown, etc.)
- [ ] Benchmark profiling mode with detailed traces
