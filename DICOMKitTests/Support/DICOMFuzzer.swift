import Foundation

/// A deterministic, seeded pseudo-random number generator (SplitMix64).
///
/// Fuzz tests must never use `SystemRandomNumberGenerator`. A crash found by
/// a non-reproducible generator is nearly worthless as a bug report: there
/// is no way to re-run the exact sequence of mutations that triggered it.
/// Recording only the seed (and the iteration index) is enough to replay any
/// mutation this type produces, on any machine, at any later time.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A deterministic mutation-based fuzzer for DICOM byte streams.
///
/// Given a fixed seed, `mutate(_:)` always applies the same sequence of
/// strategies to the same inputs, so a crash a campaign finds can be
/// reproduced exactly by re-running with the same seed and consuming the
/// same number of mutations.
struct DICOMFuzzer {
    private var rng: SplitMix64

    /// The largest byte count `mutate(_:)` will ever return. Without a cap,
    /// the length-field-corruption strategy could rewrite a length to a
    /// value the parser then tries to honor, driving unbounded allocation
    /// in the test process rather than exercising the parser's own bounds
    /// checking.
    private let maxOutputSize = 256 * 1024

    /// Other corpus entries this fuzzer may splice bytes from. The splice
    /// strategy silently no-ops when this is empty.
    var corpus: [Data] = []

    init(seed: UInt64) {
        rng = SplitMix64(seed: seed)
    }

    private enum Strategy: CaseIterable {
        case bitFlip
        case byteSubstitution
        case truncation
        case insertOrDelete
        case splice
        case lengthFieldCorruption
    }

    /// Applies one randomly chosen mutation strategy to `input` and returns
    /// the result. `input` itself is never mutated in place.
    mutating func mutate(_ input: Data) -> Data {
        guard !input.isEmpty else { return input }
        var bytes = [UInt8](input)
        switch Strategy.allCases.randomElement(using: &rng)! {
        case .bitFlip:
            let index = Int.random(in: 0..<bytes.count, using: &rng)
            let bit = UInt8(1 << Int.random(in: 0..<8, using: &rng))
            bytes[index] ^= bit

        case .byteSubstitution:
            let interesting: [UInt8] = [0x00, 0x01, 0x7F, 0x80, 0xFF]
            let index = Int.random(in: 0..<bytes.count, using: &rng)
            bytes[index] = interesting.randomElement(using: &rng)!

        case .truncation:
            let cut = Int.random(in: 0...bytes.count, using: &rng)
            bytes.removeLast(bytes.count - cut)

        case .insertOrDelete:
            if Bool.random(using: &rng) || bytes.count < 2 {
                let count = Int.random(in: 1...16, using: &rng)
                let position = Int.random(in: 0...bytes.count, using: &rng)
                bytes.insert(contentsOf: (0..<count).map { _ in UInt8.random(in: 0...255, using: &rng) }, at: position)
            } else {
                let count = min(Int.random(in: 1...16, using: &rng), bytes.count)
                let position = Int.random(in: 0...(bytes.count - count), using: &rng)
                bytes.removeSubrange(position..<(position + count))
            }

        case .splice:
            guard let donor = corpus.randomElement(using: &rng), !donor.isEmpty else { break }
            let donorBytes = [UInt8](donor)
            let donorStart = Int.random(in: 0..<donorBytes.count, using: &rng)
            let donorEnd = Int.random(in: donorStart...donorBytes.count, using: &rng)
            let donorSlice = Array(donorBytes[donorStart..<donorEnd])
            if bytes.isEmpty {
                bytes = donorSlice
            } else {
                let targetStart = Int.random(in: 0..<bytes.count, using: &rng)
                let targetEnd = Int.random(in: targetStart...bytes.count, using: &rng)
                bytes.replaceSubrange(targetStart..<targetEnd, with: donorSlice)
            }

        case .lengthFieldCorruption:
            corruptLengthField(in: &bytes)
        }
        if bytes.count > maxOutputSize {
            bytes.removeLast(bytes.count - maxOutputSize)
        }
        return Data(bytes)
    }

    /// Rewrites a 4-byte little-endian field to a value chosen to stress
    /// length arithmetic: `0`, `1`, `0xFFFFFFF0`, or `0xFFFFFFFF` (DICOM's
    /// own "undefined length" sentinel).
    ///
    /// This is the highest-yield mutation for DICOM. Every element, item,
    /// and PDU in this format is framed by an exact tag/VR/length triple;
    /// a purely random bit-flipper spends nearly all of its budget on
    /// inputs that fail the very first structural check (the Part 10
    /// preamble, or the first tag it reads) rather than ever reaching the
    /// length-driven arithmetic — offset advances, "remaining bytes" checks,
    /// buffer slicing — where the interesting bugs live. This mutation does
    /// not try to locate an actual length field by parsing the input (that
    /// would make the fuzzer depend on the very code it's attacking);
    /// instead it treats any 4-byte-aligned window as a plausible length and
    /// lets many iterations, over many corpus seeds, land on real ones.
    private mutating func corruptLengthField(in bytes: inout [UInt8]) {
        guard bytes.count >= 4 else { return }
        let offset = Int.random(in: 0...(bytes.count - 4), using: &rng)
        let replacements: [UInt32] = [0, 1, 0xFFFF_FFF0, 0xFFFF_FFFF]
        let value = replacements.randomElement(using: &rng)!
        bytes[offset] = UInt8(value & 0xFF)
        bytes[offset + 1] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 2] = UInt8((value >> 16) & 0xFF)
        bytes[offset + 3] = UInt8((value >> 24) & 0xFF)
    }
}
