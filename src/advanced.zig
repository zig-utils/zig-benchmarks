// Re-export all advanced features
pub const export_mod = @import("export");
pub const comparison = @import("comparison");
pub const memory_profiler = @import("memory_profiler");
pub const ci = @import("ci");
pub const flamegraph = @import("flamegraph");

pub const Exporter = export_mod.Exporter;
pub const ExportFormat = export_mod.ExportFormat;

pub const Comparator = comparison.Comparator;
pub const ComparisonResult = comparison.ComparisonResult;

pub const ProfilingAllocator = memory_profiler.ProfilingAllocator;
pub const MemoryStats = memory_profiler.MemoryStats;
pub const MemoryBenchmarkResult = memory_profiler.MemoryBenchmarkResult;

pub const CIHelper = ci.CIHelper;
pub const CIConfig = ci.CIConfig;
pub const OutputFormat = ci.OutputFormat;
pub const detectCIEnvironment = ci.detectCIEnvironment;

pub const FlamegraphGenerator = flamegraph.FlamegraphGenerator;
pub const ProfilerIntegration = flamegraph.ProfilerIntegration;
