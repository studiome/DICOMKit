import Foundation
import Testing
@testable import DICOMKit

/// Covers `Reader`'s bound on sequence nesting depth.
///
/// Before this bound existed, a dataset nesting sequences roughly 100-150
/// levels deep overflowed the call stack and killed the process with
/// SIGBUS -- confirmed by direct measurement: a debug build of this test
/// target crashed at a nesting depth of 110 and parsed successfully at 109
/// (see the commit message for the full bisection). Since `DICOMFile`
/// parses untrusted input, that crash is reachable from any hostile or
/// corrupt file and cannot be caught by a caller's `do`/`catch`, unlike a
/// thrown error.
struct ReaderNestingDepthTests {
    /// One level below `Reader.maxSequenceDepth` succeeds and the sequence
    /// nested at exactly the limit is still reachable.
    @Test func parsesDatasetNestedAtMaxDepth() throws {
        let data = part10File(transferSyntaxUID: TransferSyntax.implicitVRLittleEndian.uid, datasetElements: [
            nestedImplicitSequenceChain(levels: Reader.maxSequenceDepth, tag: .referencedStudySequence, leaf: implicitElement(tag: .patientName, value: "Doe^Jane"))
        ])

        let file = try DICOMFile(data: data)

        let innermost = descendNestedSequence(file.dataset, tag: .referencedStudySequence, levels: Reader.maxSequenceDepth)
        #expect(innermost?[.patientName]?.stringValue == "Doe^Jane")
    }

    /// One level beyond `Reader.maxSequenceDepth` throws
    /// `DICOMError.sequenceNestingTooDeep` instead of recursing further (and,
    /// before the fix, instead of crashing the process).
    @Test func throwsWhenNestingExceedsMaxDepth() throws {
        let data = part10File(transferSyntaxUID: TransferSyntax.implicitVRLittleEndian.uid, datasetElements: [
            nestedImplicitSequenceChain(levels: Reader.maxSequenceDepth + 1, tag: .referencedStudySequence, leaf: implicitElement(tag: .patientName, value: "Doe^Jane"))
        ])

        #expect(throws: DICOMError.sequenceNestingTooDeep) {
            try DICOMFile(data: data)
        }
    }

    /// The bound also applies via `init(datasetData:transferSyntax:)`, which
    /// skips the Part 10 preamble and File Meta Information but still runs
    /// every dataset element through the same `Reader`.
    @Test func throwsWhenNestingExceedsMaxDepthViaRawDatasetInit() throws {
        let data = nestedImplicitSequenceChain(levels: Reader.maxSequenceDepth + 1, tag: .referencedStudySequence, leaf: implicitElement(tag: .patientName, value: "Doe^Jane"))

        #expect(throws: DICOMError.sequenceNestingTooDeep) {
            try DICOMFile(datasetData: data, transferSyntax: .implicitVRLittleEndian)
        }
    }

    /// The bound also applies to `DICOMMetadataFile(url:)`, which parses a
    /// dataset from disk with its own `Reader` rather than going through
    /// `DICOMFile`.
    @Test func throwsWhenNestingExceedsMaxDepthViaMetadataFile() throws {
        let data = part10File(transferSyntaxUID: TransferSyntax.implicitVRLittleEndian.uid, datasetElements: [
            nestedImplicitSequenceChain(levels: Reader.maxSequenceDepth + 1, tag: .referencedStudySequence, leaf: implicitElement(tag: .patientName, value: "Doe^Jane"))
        ])
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("DICOMKit-\(UUID().uuidString).dcm")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: DICOMError.sequenceNestingTooDeep) {
            try DICOMMetadataFile(url: url)
        }
    }

    /// The `UN`-to-`SQ` re-interpretation path added for defined-length
    /// unknown sequences (see `Reader.parseUnknownSequence`) shares the same
    /// depth counter: nesting one level beyond the limit entirely inside a
    /// re-interpreted `UN` element's bytes still throws
    /// `sequenceNestingTooDeep`, rather than the "bytes don't parse, keep it
    /// opaque `UN`" fallback that ordinary malformed nested content gets.
    @Test func parsesUnknownSequenceReinterpretationNestedAtMaxDepth() throws {
        // One level of nesting comes from the UN-to-SQ re-interpretation
        // itself; the remaining levels are ordinary nested Implicit VR
        // sequences inside that re-interpreted content.
        let innerPayload = nestedImplicitSequenceChain(
            levels: Reader.maxSequenceDepth - 1,
            tag: .referencedStudySequence,
            leaf: implicitElement(tag: .patientName, value: "Doe^Jane")
        )
        let sequenceBytes = unknownSequenceItemBytes(innerPayload)
        let data = part10File(transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid, datasetElements: [
            element(tag: .referencedStudySequence, vr: .UN, value: sequenceBytes)
        ])

        let file = try DICOMFile(data: data)

        let sequenceElement = try #require(file.dataset[.referencedStudySequence])
        #expect(sequenceElement.vr == .SQ)
        let innermost = descendNestedSequence(file.dataset, tag: .referencedStudySequence, levels: Reader.maxSequenceDepth)
        #expect(innermost?[.patientName]?.stringValue == "Doe^Jane")
    }

    @Test func throwsWhenUnknownSequenceReinterpretationExceedsMaxDepth() throws {
        let innerPayload = nestedImplicitSequenceChain(
            levels: Reader.maxSequenceDepth,
            tag: .referencedStudySequence,
            leaf: implicitElement(tag: .patientName, value: "Doe^Jane")
        )
        let sequenceBytes = unknownSequenceItemBytes(innerPayload)
        let data = part10File(transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid, datasetElements: [
            element(tag: .referencedStudySequence, vr: .UN, value: sequenceBytes)
        ])

        #expect(throws: DICOMError.sequenceNestingTooDeep) {
            try DICOMFile(data: data)
        }
    }
}

/// Builds `levels` nested Implicit VR undefined-length sequences (each
/// holding a single item containing the next level), with `leaf` at the
/// center. Returns a complete dataset element, so it can be dropped directly
/// into `datasetElements:`.
func nestedImplicitSequenceChain(levels: Int, tag: DICOMTag, leaf: Data) -> Data {
    var payload = leaf
    for _ in 0..<levels {
        payload = implicitUndefinedLengthSequence(tag: tag, itemElements: [payload])
    }
    return payload
}

/// Descends `levels` times through `tag`'s first sequence item, returning
/// the dataset reached at the bottom (or `nil` if the chain is shorter than
/// `levels`).
func descendNestedSequence(_ dataset: DICOMDataset, tag: DICOMTag, levels: Int) -> DICOMDataset? {
    var current: DICOMDataset? = dataset
    for _ in 0..<levels {
        current = current?[tag]?.sequenceItems?.first
    }
    return current
}

/// A raw Implicit VR item header (`FFFE,E000`) wrapping `payload`, matching
/// the shape `Reader.parseUnknownSequence` expects for a defined-length `UN`
/// element's value bytes: one or more items with no outer sequence tag or
/// length, since the `UN` element's own header already supplies those.
///
/// (`DICOMReadOptionsTests.swift` has an equivalent `private` helper that
/// isn't visible from this file.)
func unknownSequenceItemBytes(_ payload: Data) -> Data {
    var data = uint16(0xFFFE) + uint16(0xE000)
    data.append(uint32(UInt32(payload.count)))
    data.append(payload)
    return data
}
