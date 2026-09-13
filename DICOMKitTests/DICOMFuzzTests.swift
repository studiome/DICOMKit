import Foundation
import Testing
@testable import DICOMKit

/// Fuzz coverage for DICOMKit's parsers of untrusted input.
///
/// The invariant under test, everywhere in this file, is: **for any byte
/// sequence, a decoder either returns a value or throws — it must never
/// trap, and it must always terminate.** Hand review already found
/// trap-on-malformed-input defects in this codebase (an unchecked
/// `UInt16(value.count)` conversion, an index-out-of-range on an empty
/// array); this campaign exists to find the rest.
///
/// A Swift trap (an unchecked array subscript, a failed integer conversion,
/// `fatalError`, `preconditionFailure`, …) **cannot be caught** with
/// `do`/`catch` — it kills the process immediately. So a crash this fuzzer
/// finds does not surface as a failed `#expect`; it surfaces as the whole
/// `swift test` process dying mid-run, with no Swift code left to run
/// afterward to report *what* it was doing when it died. That is the
/// intended signal (the test process dying IS the finding), but it also
/// means reproducibility has to be engineered in up front: every mutated
/// input is written to a fixed scratch file *before* it is handed to the
/// decoder, specifically so that whatever is on disk at that path when the
/// process dies is the exact input that killed it. Combined with a fixed
/// PRNG seed (see `DICOMFuzzer`/`SplitMix64`), this makes a crash a
/// developer hits in a long local campaign reproducible: rerun with the
/// same `DICOMKIT_FUZZ_SEED`, or just open the saved file directly.
struct DICOMFuzzTests {
    @Test func fileParserNeverTrapsOnMutatedInput() throws {
        let corpus = try fileParserFuzzCorpus()
        let seed = fuzzSeed()
        let iterations = fuzzIterations(default: 2000)
        fuzzRun(name: "file-parser", corpus: corpus, iterations: iterations, seed: seed) { data in
            do {
                let file = try DICOMFile(data: data)
                // The one invariant checkable on a *successful* parse: the
                // dataset (and every nested sequence item's dataset) can be
                // walked in full — touching every decoded element, which is
                // where a trap deferred until access (rather than during
                // parsing) would show up — and reports a finite, consistent
                // element count.
                try assertDatasetIsSafeToIterate(file.dataset)
                try assertDatasetIsSafeToIterate(file.metaInformation)
            } catch let violation as FuzzInvariantViolation {
                throw violation
            } catch {
                // Any other thrown error is the correct, expected outcome
                // for malformed/mutated input: the parser rejected it
                // instead of trapping on it.
            }
        }
    }

    @Test func upperLayerPDUDecoderNeverTrapsOnMutatedInput() throws {
        let corpus = try ulpduFuzzCorpus()
        let seed = fuzzSeed()
        let iterations = fuzzIterations(default: 4000)
        fuzzRun(name: "ulpdu", corpus: corpus, iterations: iterations, seed: seed) { data in
            do {
                // `DICOMULPDU` is a plain enum of value types (strings,
                // arrays, fixed-width integers): fully decoding one, as
                // `decode` does, already exercises everything the fuzzer can
                // reach — there's no lazily-evaluated storage left to trap
                // on access the way `DICOMFile`'s pixel data path has.
                _ = try DICOMULPDU.decode(data)
            } catch {
                // Expected: malformed/mutated input rejected instead of
                // trapping on it.
            }
        }
    }

    @Test func dimseCommandSetDecoderNeverTrapsOnMutatedInput() throws {
        let corpus = try dimseFuzzCorpus()
        let seed = fuzzSeed()
        let iterations = fuzzIterations(default: 4000)
        fuzzRun(name: "dimse", corpus: corpus, iterations: iterations, seed: seed) { data in
            do {
                _ = try DICOMDIMSECommand.decodeCommandSet(data)
            } catch {
                // Expected: malformed/mutated input rejected instead of
                // trapping on it.
            }
        }
    }
}

// MARK: - Shared fuzz harness

/// Signals that a decoder returned successfully but violated an invariant
/// this test can actually check (as opposed to simply throwing, which is
/// always acceptable). Distinct from every error type the library itself
/// throws, so `fuzzRun` can tell "the library rejected this input" (ignore)
/// apart from "the library accepted input it should not have, or its output
/// is internally inconsistent" (a real finding).
struct FuzzInvariantViolation: Error, CustomStringConvertible {
    let description: String
}

/// Recursively walks `dataset` and every dataset nested inside its sequence
/// items, counting elements as it goes. Throws if iteration disagrees with
/// `count`, which would mean `DICOMDataset`'s storage and its `Sequence`
/// conformance have gone out of sync for this (fuzzer-produced) input.
func assertDatasetIsSafeToIterate(_ dataset: DICOMDataset) throws {
    var visited = 0
    for element in dataset {
        visited += 1
        if let items = element.sequenceItems {
            for item in items {
                try assertDatasetIsSafeToIterate(item)
            }
        }
    }
    guard visited == dataset.count else {
        throw FuzzInvariantViolation(description: "iterating a dataset visited \(visited) elements but count reports \(dataset.count)")
    }
}

/// Reads `DICOMKIT_FUZZ_SEED`, falling back to a fixed value so a green run
/// of `swift test` stays green: without a fixed default, a random seed could
/// happen to land on a not-yet-fixed defect and make CI flaky.
func fuzzSeed() -> UInt64 {
    ProcessInfo.processInfo.environment["DICOMKIT_FUZZ_SEED"].flatMap(UInt64.init) ?? 0xC0FF_EE00_BADF_00D5
}

/// Reads `DICOMKIT_FUZZ_ITERATIONS`, falling back to `defaultValue` when
/// unset or unparseable. A developer sets the environment variable to run a
/// long campaign; CI and an ordinary local `swift test` use the default.
func fuzzIterations(default defaultValue: Int) -> Int {
    ProcessInfo.processInfo.environment["DICOMKIT_FUZZ_ITERATIONS"].flatMap(Int.init) ?? defaultValue
}

/// Runs `iterations` mutations of entries from `corpus` through `decode`.
///
/// `decode` must itself swallow every error it considers an acceptable
/// outcome (i.e. everything the library throws) and only let a
/// `FuzzInvariantViolation` escape. Anything else escaping is a programmer
/// error in the test, not a fuzz finding, and is allowed to propagate.
///
/// Before each call to `decode`, the candidate input is written to a fixed
/// "in-flight" file. If `decode` traps, the process dies right there with no
/// chance to run any code afterward — so that file, at that path, already
/// holds the reproducer by construction. If `decode` returns normally (or
/// throws an acceptable error), the loop continues; if the whole campaign
/// finishes cleanly, the in-flight file is removed since it no longer
/// indicates anything.
func fuzzRun(
    name: String,
    corpus: [Data],
    iterations: Int,
    seed: UInt64,
    sourceLocation: SourceLocation = #_sourceLocation,
    decode: (Data) throws -> Void
) {
    precondition(!corpus.isEmpty, "fuzz corpus must not be empty")
    var fuzzer = DICOMFuzzer(seed: seed)
    fuzzer.corpus = corpus
    let inFlightURL = FileManager.default.temporaryDirectory.appendingPathComponent("dicomkit-fuzz-\(name)-inflight.bin")
    for index in 0..<iterations {
        let base = corpus[index % corpus.count]
        let mutated = fuzzer.mutate(base)
        try? mutated.write(to: inFlightURL)
        do {
            try decode(mutated)
        } catch let violation as FuzzInvariantViolation {
            let savedURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("dicomkit-fuzz-\(name)-failure-seed\(seed)-iter\(index).bin")
            try? mutated.write(to: savedURL)
            let message = "DICOMKit fuzz failure [\(name)]: seed=\(seed) iteration=\(index)/\(iterations): \(violation.description); offending input saved to \(savedURL.path)"
            print(message)
            Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
        } catch {
            // Should not happen: `decode` is documented to swallow every
            // error except `FuzzInvariantViolation`. Surface it as a test
            // failure rather than silently discarding it.
            Issue.record("fuzz harness received an unexpected error from decode: \(error) (seed \(seed), iteration \(index))", sourceLocation: sourceLocation)
        }
    }
    try? FileManager.default.removeItem(at: inFlightURL)
}

// MARK: - File parser corpus

/// A seed corpus for ``DICOMFile/init(data:)`` covering every dataset
/// encoding the reader supports: a real acquisition, Explicit VR Little
/// Endian, Implicit VR Little Endian with an undefined-length sequence,
/// Explicit VR Big Endian, a deflated dataset, a nested sequence, and an
/// encapsulated Pixel Data stream.
func fileParserFuzzCorpus() throws -> [Data] {
    var corpus: [Data] = []

    corpus.append(try Data(contentsOf: fixtureURL(resource: "CT_small", extension: "dcm")))

    corpus.append(part10File(
        transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid,
        datasetElements: [
            element(tag: .patientName, vr: .PN, value: "Doe^Jane"),
            element(tag: .rows, vr: .US, value: uint16(64)),
            element(tag: .columns, vr: .US, value: uint16(64))
        ]
    ))

    corpus.append(part10File(
        transferSyntaxUID: TransferSyntax.implicitVRLittleEndian.uid,
        datasetElements: [
            implicitElement(tag: .patientName, value: "Doe^Jane"),
            implicitUndefinedLengthSequence(
                tag: .referencedStudySequence,
                itemElements: [implicitElement(tag: .referencedSOPClassUID, value: "1.2.840.10008.5.1.4.1.1.2")]
            )
        ]
    ))

    var bigEndianData = Data(repeating: 0, count: 128)
    bigEndianData.append(Data("DICM".utf8))
    bigEndianData.append(element(tag: .transferSyntaxUID, vr: .UI, value: TransferSyntax.explicitVRBigEndian.uid))
    bigEndianData.append(fuzzBigEndianElement(tag: .patientName, vr: .PN, value: Data("Doe^Jane".utf8)))
    bigEndianData.append(fuzzBigEndianElement(tag: .rows, vr: .US, value: Data([0x00, 0x40])))
    corpus.append(bigEndianData)

    var deflatedData = Data(repeating: 0, count: 128)
    deflatedData.append(Data("DICM".utf8))
    deflatedData.append(element(tag: .transferSyntaxUID, vr: .UI, value: TransferSyntax.deflatedExplicitVRLittleEndian.uid))
    deflatedData.append(try DeflateCodec.deflateRaw(element(tag: .patientName, vr: .PN, value: "Doe^Jane")))
    corpus.append(deflatedData)

    // A sequence nested inside another sequence's item.
    let innerSequence = implicitUndefinedLengthSequence(
        tag: .referencedStudySequence,
        itemElements: [implicitElement(tag: .referencedSOPClassUID, value: "1.2.840.10008.5.1.4.1.1.4")]
    )
    corpus.append(part10File(
        transferSyntaxUID: TransferSyntax.implicitVRLittleEndian.uid,
        datasetElements: [
            implicitUndefinedLengthSequence(
                tag: DICOMTag(group: 0x0008, element: 0x1140),
                itemElements: [innerSequence]
            )
        ]
    ))

    corpus.append(part10File(
        transferSyntaxUID: TransferSyntax.jpegBaseline.uid,
        datasetElements: [
            element(tag: .rows, vr: .US, value: uint16(2)),
            element(tag: .columns, vr: .US, value: uint16(2)),
            element(tag: .samplesPerPixel, vr: .US, value: uint16(1)),
            element(tag: .photometricInterpretation, vr: .CS, value: "MONOCHROME2"),
            element(tag: .bitsAllocated, vr: .US, value: uint16(8)),
            encapsulatedPixelData(basicOffsetTable: Data([0, 0, 0, 0]), fragments: [Data([0xFF, 0xD8, 0xFF, 0xD9, 0x00, 0x00])])
        ]
    ))

    return corpus
}

/// A standalone Explicit VR Big Endian element encoder for the fuzz corpus.
/// (`DICOMFileReaderTests.swift` has an equivalent `private` helper that
/// isn't visible from this file.)
private func fuzzBigEndianElement(tag: DICOMTag, vr: DICOMVR, value: Data) -> Data {
    var result = Data([
        UInt8(tag.group >> 8), UInt8(tag.group & 0xFF),
        UInt8(tag.element >> 8), UInt8(tag.element & 0xFF)
    ])
    result.append(Data(vr.rawValue.utf8))
    if vr.uses32BitLength {
        result.append(Data([0, 0, 0, 0]))
        let length = UInt32(value.count)
        result.append(Data([UInt8(length >> 24), UInt8(length >> 16), UInt8(length >> 8), UInt8(length & 0xFF)]))
    } else {
        let length = UInt16(value.count)
        result.append(Data([UInt8(length >> 8), UInt8(length & 0xFF)]))
    }
    result.append(value)
    return result
}

// MARK: - Upper Layer PDU corpus

/// A seed corpus of real, wire-encoded Upper Layer PDUs (PS3.8): an
/// A-ASSOCIATE-RQ exercising presentation contexts, role selection, an
/// asynchronous operations window, and user identity negotiation; an
/// A-ASSOCIATE-AC; an A-ASSOCIATE-RJ; a P-DATA-TF with several PDVs; a
/// release request and response; and an abort.
func ulpduFuzzCorpus() throws -> [Data] {
    var corpus: [Data] = []

    let request = DICOMAssociationRequest(
        calledAETitle: "CALLED_AE",
        callingAETitle: "CALLING_AE",
        presentationContexts: [
            DICOMPresentationContext(
                id: 1,
                abstractSyntaxUID: "1.2.840.10008.5.1.4.1.1.2",
                transferSyntaxUIDs: [TransferSyntax.explicitVRLittleEndian.uid, TransferSyntax.implicitVRLittleEndian.uid]
            ),
            DICOMPresentationContext(id: 3, abstractSyntaxUID: "1.2.840.10008.1.1", transferSyntaxUIDs: [TransferSyntax.implicitVRLittleEndian.uid])
        ],
        userIdentity: DICOMUserIdentityNegotiation(identity: .usernameAndPassword(username: "user", password: "pass"), positiveResponseRequested: true),
        roleSelections: [DICOMRoleSelection(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", supportsSCURole: true, supportsSCPRole: false)],
        asynchronousOperationsWindow: DICOMAsynchronousOperationsWindow(maximumInvoked: 1, maximumPerformed: 1)
    )
    corpus.append(try DICOMULPDU.associationRequest(request).encoded())

    let acceptance = DICOMAssociationAcceptance(
        calledAETitle: "CALLED_AE",
        callingAETitle: "CALLING_AE",
        presentationContexts: [
            DICOMPresentationContextAcceptance(id: 1, result: .acceptance, transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid)
        ],
        roleSelections: [DICOMRoleSelection(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", supportsSCURole: true, supportsSCPRole: true)],
        asynchronousOperationsWindow: DICOMAsynchronousOperationsWindow(maximumInvoked: 1, maximumPerformed: 1)
    )
    corpus.append(try DICOMULPDU.associationAcceptance(acceptance).encoded())

    corpus.append(try DICOMULPDU.associationRejection(
        DICOMAssociationRejection(result: .permanent, source: .serviceUser, reason: 1)
    ).encoded())

    corpus.append(try DICOMULPDU.pData([
        DICOMPDataValue(contextID: 1, isCommand: true, isLastFragment: false, data: Data([0x01, 0x02, 0x03, 0x04])),
        DICOMPDataValue(contextID: 1, isCommand: false, isLastFragment: true, data: Data(repeating: 0xAB, count: 64)),
        DICOMPDataValue(contextID: 3, isCommand: true, isLastFragment: true, data: Data([0xFF]))
    ]).encoded())

    corpus.append(try DICOMULPDU.releaseRequest.encoded())
    corpus.append(try DICOMULPDU.releaseResponse.encoded())
    corpus.append(try DICOMULPDU.abort(source: 0, reason: 0).encoded())

    return corpus
}

// MARK: - DIMSE command set corpus

/// A seed corpus covering every DIMSE command ``DICOMDIMSECommand`` can
/// currently encode, so the decoder's fuzz coverage starts from something
/// resembling every wire shape it must understand.
func dimseFuzzCorpus() throws -> [Data] {
    try [
        DICOMDIMSECommand.cEchoRequest(messageID: 1),
        .cEchoResponse(messageIDBeingRespondedTo: 1, status: .success),
        .cStoreRequest(messageID: 1, affectedSOPClassUID: "1.2.840.10008.5.1.4.1.1.2", affectedSOPInstanceUID: "1.2.3.4.5"),
        .cStoreResponse(messageIDBeingRespondedTo: 1, status: .success),
        .cFindRequest(messageID: 1, affectedSOPClassUID: "1.2.840.10008.5.1.4.1.2.2.1"),
        .cFindResponse(messageIDBeingRespondedTo: 1, status: .pending, identifierFollows: true, errorComment: nil),
        .cFindResponse(messageIDBeingRespondedTo: 1, status: .errorCannotUnderstand, identifierFollows: false, errorComment: "malformed identifier"),
        .cMoveRequest(messageID: 1, affectedSOPClassUID: "1.2.840.10008.5.1.4.1.2.2.2", moveDestination: "DEST_AE"),
        .cMoveResponse(
            messageIDBeingRespondedTo: 1,
            status: .success,
            identifierFollows: false,
            subOperations: DICOMSubOperationCounts(remaining: 0, completed: 1, failed: 0, warning: 0),
            errorComment: nil
        ),
        .cGetRequest(messageID: 1, affectedSOPClassUID: "1.2.840.10008.5.1.4.1.2.2.3"),
        .cGetResponse(
            messageIDBeingRespondedTo: 1,
            status: .refusedOutOfResources,
            identifierFollows: false,
            subOperations: nil,
            errorComment: "out of resources"
        ),
        .cCancelRequest(messageIDBeingRespondedTo: 1)
    ].map { try $0.encodedCommandSet() }
}
