import Foundation

// DICOMKitBenchmark: a dependency-free performance harness for DICOMKit core
// (depends on the `DICOMKit` product only -- see Package.swift and
// Docs/benchmarks.md for why). This is a developer tool for tracking
// performance on one machine over time, not a `swift test` gate: see
// `BenchmarkHarness.swift` and `Docs/benchmarks.md` for why timing
// assertions don't belong in the test suite.
//
// Usage:
//   swift run -c release DICOMKitBenchmark [iterations]
//   DICOMKIT_BENCHMARK_ITERATIONS=50 swift run -c release DICOMKitBenchmark
//
// A positional argument takes precedence over the environment variable,
// which takes precedence over the default below. Always build `-c release`:
// a parser's debug-build numbers are dominated by unoptimized bounds
// checking and array copy-on-write overhead, and would misrepresent the
// library's actual performance.

/// Default iteration count: enough for a stable median without the default
/// run taking more than a few seconds on ordinary developer hardware. Raise
/// it (via the CLI argument or environment variable above) for a steadier
/// number at the cost of runtime.
let defaultIterations = 15

func resolveIterations() -> Int {
    if CommandLine.arguments.count > 1, let fromArgument = Int(CommandLine.arguments[1]), fromArgument > 0 {
        return fromArgument
    }
    if let fromEnvironment = ProcessInfo.processInfo.environment["DICOMKIT_BENCHMARK_ITERATIONS"], let parsed = Int(fromEnvironment), parsed > 0 {
        return parsed
    }
    return defaultIterations
}

let iterations = resolveIterations()
print("DICOMKitBenchmark -- iterations=\(iterations)")
print("")

Benchmarks.runAll(iterations: iterations)

print("")
// Forces every benchmark body's result to be observed, so the optimizer in
// a release build can't discard the work being measured. See `Sink` in
// BenchmarkHarness.swift.
print("(sink=\(Benchmark.sinkValue), ignore -- present only to defeat dead-code elimination)")
