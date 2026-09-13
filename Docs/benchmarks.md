# Performance benchmarks

`DICOMKitBenchmark` (an executable target, `DICOMKitBenchmark/`, depending on
`DICOMKit` alone) measures a handful of operations a viewer's hot path hits
repeatedly: opening a file, opening a series, decoding frames, and rendering
one. See `DICOMKitBenchmark/BenchmarkHarness.swift` for the methodology
(warmup pass discarded, fixed repetition count, median/min/max reported
rather than a mean) and `DICOMKitBenchmark/Benchmarks.swift` for what each
benchmark builds and why.

**This is a developer tool, not a `swift test` gate.** `swift test` asserts
correctness, never timing: a timing assertion on a shared CI runner is
flaky by construction (another job stealing CPU, a thermal throttle, a noisy
neighbor VM), and a flaky test is worse than no test at all — it gets
disabled by the next person who trips over it, and once disabled nobody
re-enables it, so the coverage is gone for good. What follows is a recorded
baseline for a human to compare a later run against on the *same* machine,
not a claim about DICOMKit's performance in general or a threshold CI
enforces.

## Re-running it

```bash
swift build -c release
swift run -c release DICOMKitBenchmark            # default iteration count
swift run -c release DICOMKitBenchmark 50         # override: 50 iterations
DICOMKIT_BENCHMARK_ITERATIONS=50 swift run -c release DICOMKitBenchmark
```

Always build `-c release`. A debug build's numbers are dominated by
unoptimized bounds checking and array copy-on-write overhead — on this
machine the debug build reported the `CT_small.dcm` parse at roughly 4-10x
the release figure below, and the render benchmark at roughly 45x, which
would misrepresent the library entirely if mistaken for a real number.

A CLI argument overrides the `DICOMKIT_BENCHMARK_ITERATIONS` environment
variable, which overrides the built-in default of 15. The default keeps the
whole run to about a second and a half on the baseline machine below;
raising the iteration count trades runtime for a steadier median.

## Baseline

Recorded 2026-09-13.

| | |
| --- | --- |
| Machine | Apple M3, 8 cores (4 performance + 4 efficiency) |
| OS | macOS 26.6.2 (build 25G83) |
| Swift | Apple Swift 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101), target `arm64-apple-macosx26.0` |
| Build configuration | `swift build -c release` |
| Command | `swift run -c release DICOMKitBenchmark 30` |
| Iterations (n) | 30 (plus one discarded warmup per benchmark) |

Three consecutive runs stayed within about 10% of each other on every line
except the very first cold process launch after a fresh build, which ran
noticeably slower across the board (see "What surprised me" below) — the
table records the second of three runs, chosen because a first-launch
artifact makes a worse baseline than an unremarkable steady-state one.

| Benchmark | Input size | Median | Min | Max |
| --- | --- | ---: | ---: | ---: |
| Dataset parse: `CT_small.dcm` | 39,206 bytes, 258 elements | 0.0848 ms | 0.0838 ms | 0.0942 ms |
| Dataset parse: large flat dataset | 162,728 bytes, 8,000 elements | 2.7498 ms | 2.5784 ms | 3.4383 ms |
| Dataset parse: deeply nested sequences | 1,344 bytes, depth 32 | 0.0350 ms | 0.0346 ms | 0.0362 ms |
| Series open: 64 instances | 64 × 39,206 bytes | 5.5240 ms | 5.2557 ms | 5.8406 ms |
| Metadata-only open: `CT_small.dcm` | 39,206 bytes, 258 elements | 0.1050 ms | 0.1004 ms | 0.1225 ms |
| Per-frame decode: 16 native frames | 16 × 512×512, 16-bit | 0.4679 ms (0.0292 ms/frame) | 0.3921 ms | 0.6745 ms |
| Render: `cgImage`, 16-bit monochrome | 512×512, 1 frame | 2.4481 ms/frame | 2.3094 ms | 2.6845 ms |

Throughput is derivable from the input-size column: for example, the large
flat dataset parses roughly 2.9 million elements/second (8,000 elements /
2.7498 ms), and the series-open benchmark averages roughly 86 µs/instance
(5.5240 ms / 64).

### What N means for series open

64 instances of `CT_small.dcm`, parsed back to back with `DICOMFile(data:)`.
64 is on the low end of a real chest CT series (commonly a hundred to
several hundred slices) — chosen so the *default* benchmark run finishes in
about a second, not as a claim that 64 is a typical series size. There is no
second real fixture to substitute for genuinely distinct instances, so this
reuses `CT_small.dcm`'s bytes rather than inventing per-instance variation
that isn't the point of the measurement; see the caveat under "What
surprised me" about what that repetition does and doesn't tell you.

### How the fixture was located

`CT_small.dcm` is a `DICOMKitTests` resource, reached from test code through
`Bundle.module` — a bundle SwiftPM synthesizes per-target, which an
executable target in a different target has no way to see. Rather than
synthesize a stand-in for the one benchmark that specifically wants to
compare a full parse against a metadata-only open of *the same real bytes*,
`DICOMKitBenchmark/Fixtures.swift` resolves the fixture with `#filePath`,
walking up from its own known location in the repository
(`DICOMKitBenchmark/Fixtures.swift` → repo root →
`DICOMKitTests/Fixtures/CT_small.dcm`). This only works from a source
checkout, which is an acceptable trade for a benchmark a developer runs from
the repository — every other benchmark here synthesizes its own input
instead, both to control its size and to avoid that constraint.

## What surprised me

**Metadata-only open's saving is real but easy to underestimate from this
fixture alone, because `CT_small.dcm`'s own Pixel Data is tiny.** The
recorded baseline shows `DICOMMetadataFile` at roughly 2x faster than a full
`DICOMFile` parse (0.105 ms vs. 0.085 ms) for `CT_small.dcm` — a real
improvement, but not a dramatic one. That's because `CT_small.dcm` is
128×128 16-bit, so its Pixel Data value is only about 32 KB out of the
file's 39,206 bytes; skipping it barely moves the needle when the other 258
elements' parsing dominates. As a sanity check, I ran the same comparison
(outside the committed benchmark, since it isn't one of the specified inputs)
against a synthesized 512×512×64-frame dataset — 32 MB of Pixel Data — on
the same machine: full parse took about 0.79 ms, metadata-only open took
about 0.05 ms, a roughly 16x difference. The saving scales with how much of
the file *is* Pixel Data, which is exactly what `DICOMMetadataFile` is
designed to skip — so its benefit is proportionally small on a small image
and large on anything resembling a real multi-frame series or a big-matrix
CT/MR slice. Reading the 2x figure above in isolation would understate how
much this path is worth protecting for the multi-frame case the roadmap
calls out it for.

**Rendering one frame costs far more than decoding one.** Per-frame decode
of a native (uncompressed) frame is about 0.029 ms; rendering that same-sized
frame to a `CGImage` is about 2.45 ms — roughly 85x slower. This isn't
unreasonable on its face (decode is a byte slice; render walks every sample,
masks/sign-extends/rescales/windows it, and builds a `CGImage`), but the gap
is large enough that a cine or scroll interaction bottlenecks entirely on
`cgImage(windowCenter:windowWidth:)`, not on `pixelDataFrames`. Anyone
chasing scroll-performance complaints should look here first, not at parsing.

**A tight loop of identical parses is not a stand-in for opening N distinct
files.** Series-open averages about 86 µs per instance inside its
64-iteration loop, well under the 85 µs the standalone `CT_small.dcm`
benchmark's own median suggests, even though both are parsing byte-for-byte
identical input. The likely explanation is that parsing the same `Data`
back-to-back keeps its pages and the relevant code paths hot in cache in a
way a real series — 64 *different* files with different bytes at different
addresses — would not benefit from nearly as much. Treat the per-instance
figure derived from series-open as an optimistic lower bound, not a
prediction for real, distinct files; the standalone single-file benchmark is
the more representative number for that.

**The very first process launch after a fresh build runs slower across
every benchmark**, independent of each benchmark's own internal warmup pass.
Three consecutive `swift run -c release DICOMKitBenchmark 30` invocations
right after each other agreed within about 10%, but the very first
invocation after `swift build -c release` measured `CT_small.dcm`'s parse at
roughly 2.6x the steady-state figure above. Each benchmark's warmup call
already exercises the exact code path being timed, so this isn't a gap in
the harness's own methodology — it looks like a one-time, process-level cost
(dyld/page cache, not anything `DICOMKit` controls) that a within-process
warmup can't absorb. This is exactly the kind of run-to-run variance the top
of this document says makes a timing assertion in `swift test` a bad idea:
compare medians across full runs, not single samples, and expect the first
run after a build to be an outlier.
