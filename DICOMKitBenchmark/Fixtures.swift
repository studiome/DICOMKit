import Foundation

/// Locates the shared test fixture this benchmark reuses.
///
/// `CT_small.dcm` is copied into `DICOMKitTests`' resource bundle by
/// `Package.swift` (`.copy("Fixtures")` on the `DICOMKitTests` target), which
/// is how test code reaches it via `Bundle.module`. An executable target has
/// no resource bundle of its own and cannot see another target's
/// `Bundle.module` -- `Bundle.module` is a file SwiftPM synthesizes
/// per-target, not a shared registry -- so that path is closed here.
///
/// Two options remain: synthesize equivalent bytes in this benchmark, or
/// resolve the real fixture by a source-relative path using `#filePath`.
/// This file picks the latter for the one benchmark that specifically wants
/// *this* real, previously-captured CT slice (128x128, 16-bit MONOCHROME2,
/// 258 elements) rather than a synthetic stand-in: comparing a full parse
/// against a metadata-only open of the exact same bytes is the point of that
/// comparison, and `#filePath` is resolved by the compiler at compile time
/// from this file's own location in the repository, so it costs nothing at
/// run time and needs no bundle machinery. Every other benchmark
/// (large dataset, deep nesting, multi-frame pixel data, series-open)
/// synthesizes its own input instead, both to control its size precisely
/// and to keep this benchmark runnable from a copy of just this directory.
///
/// This does mean the fixture-backed benchmarks only run from a source
/// checkout (an installed/relocated binary would not carry `DICOMKitTests/`
/// alongside it) -- acceptable for a developer-run benchmark, unlike
/// `Bundle.module`, which works from a relocated build.
enum Fixtures {
    /// The absolute path to `DICOMKitTests/Fixtures/CT_small.dcm`, resolved
    /// relative to this source file's location in the repository:
    /// `<repo>/DICOMKitBenchmark/Fixtures.swift` -> `<repo>/DICOMKitTests/Fixtures/CT_small.dcm`.
    static var ctSmallURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // DICOMKitBenchmark/
            .deletingLastPathComponent() // <repo root>
            .appendingPathComponent("DICOMKitTests/Fixtures/CT_small.dcm")
    }

    /// Loads `CT_small.dcm`'s bytes, or terminates the benchmark run with a
    /// clear diagnostic: an unrunnable benchmark should fail loudly rather
    /// than silently skip a measurement.
    static func loadCTSmall() -> Data {
        let url = ctSmallURL
        guard let data = try? Data(contentsOf: url) else {
            fatalError("Could not load fixture at \(url.path). Run this benchmark from a full DICOMKit checkout.")
        }
        return data
    }
}
