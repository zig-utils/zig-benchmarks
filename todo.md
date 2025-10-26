# Zig Benchmark Framework - TODO

## Core Implementation
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

## Examples & Documentation
- [x] Create example benchmarks demonstrating usage
- [x] Write comprehensive README with documentation
- [ ] Add inline documentation and comments
- [ ] Create advanced examples (async, allocators, etc.)

## Build & Testing
- [x] Create build.zig for the project
- [ ] Add unit tests for statistical functions
- [ ] Add integration tests for benchmark runner
- [ ] Test on different platforms

## Advanced Features (Future)
- [ ] JSON/CSV output export
- [ ] Historical comparison (compare against saved baselines)
- [ ] Memory profiling integration
- [ ] Flamegraph generation support
- [ ] CI/CD integration helpers
- [ ] Regression detection
