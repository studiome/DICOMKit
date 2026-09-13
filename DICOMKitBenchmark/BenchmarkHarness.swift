import Foundation

/// A minimal, dependency-free timing harness.
///
/// Methodology, deliberately simple and stated here rather than left
/// implicit in the numbers:
///
/// - A **warmup pass** runs the operation once before any sample is
///   recorded, discarding its result. This absorbs one-time costs (page-ins,
///   lazy global initialization, allocator warm-up) that would otherwise
///   inflate the first timed sample and make the run's variance look worse
///   than the steady-state operation actually is.
/// - A **fixed number of repetitions** then runs the same operation,
///   recording each duration with `ContinuousClock`, which is monotonic and
///   unaffected by wall-clock adjustments.
/// - The report is the **median**, plus min/max, never the mean. A shared
///   CI runner or a laptop that spins up a fan mid-run produces occasional
///   scheduling hiccups; a single such hiccup skews a mean substantially but
///   barely moves a median, so the median is the number worth comparing run
///   to run. Min/max are kept alongside it so a caller can see how much the
///   samples actually spread.
/// - Every report line prints the **input size** next to the timing so
///   throughput (bytes/sec, frames/sec, elements/sec) can be derived by
///   whoever reads the numbers later, without re-running anything.
enum Benchmark {
    /// One measured result: a name, a description of the input size that
    /// produced it, the iteration count, and the median/min/max durations.
    struct Result {
        let name: String
        let inputSize: String
        let iterations: Int
        let median: Duration
        let min: Duration
        let max: Duration

        /// A human-readable report line: name, input size, iteration count,
        /// and median (min-max), all in milliseconds.
        var report: String {
            "\(name)  [\(inputSize)]  n=\(iterations)  median=\(Self.milliseconds(median))  min=\(Self.milliseconds(min))  max=\(Self.milliseconds(max))"
        }

        private static func milliseconds(_ duration: Duration) -> String {
            let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
            return String(format: "%.4fms", seconds * 1000)
        }
    }

    /// A sink that every benchmark body's result feeds into.
    ///
    /// Swift's optimizer is entitled to discard a pure computation whose
    /// result nothing observes; in a release build that could silently
    /// delete the very work a benchmark exists to measure. Folding every
    /// body's result into this accumulator, and printing it once at the end
    /// of the run (see `main.swift`), gives the optimizer an observable use
    /// for the result without adding any real per-iteration cost.
    private final class Sink: @unchecked Sendable {
        private(set) var value: Int = 0
        func accumulate(_ next: Int) { value ^= next }
    }

    private static let sink = Sink()

    /// The accumulated sink value. Printed once at the end of the run; the
    /// number itself is meaningless; see `Sink`.
    static var sinkValue: Int { sink.value }

    /// Runs `body` once as an untimed warmup, then `iterations` more times
    /// with each duration recorded, and returns the median/min/max.
    ///
    /// `body` returns an `Int` derived from its result (a byte count, a
    /// pixel count, a frame count -- whatever is cheap to compute) purely so
    /// `Sink` has something to fold in; the benchmark reports operate on the
    /// separately-supplied `inputSize` description, not on this value.
    @discardableResult
    static func measure(
        name: String,
        inputSize: String,
        iterations: Int,
        body: () -> Int
    ) -> Result {
        // Warmup: run once, discard the result entirely.
        _ = body()

        let clock = ContinuousClock()
        var samples: [Duration] = []
        samples.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let start = clock.now
            let value = body()
            let elapsed = clock.now - start
            sink.accumulate(value)
            samples.append(elapsed)
        }
        samples.sort()
        let median = samples[samples.count / 2]
        let result = Result(name: name, inputSize: inputSize, iterations: iterations, median: median, min: samples.first!, max: samples.last!)
        print(result.report)
        return result
    }
}
