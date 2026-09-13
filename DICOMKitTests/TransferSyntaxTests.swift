import Foundation
import Testing
@testable import DICOMKit

/// Tests for the three High-Throughput JPEG 2000 (HTJ2K) transfer syntaxes.
///
/// Before these cases existed, a dataset declaring any of these UIDs failed
/// to open at all: `TransferSyntax(uid:)` produced `.unknown`, `isSupported`
/// was `false`, and `DICOMFile(data:)` threw. That's the regression these
/// tests guard against — not decoding, just being able to open the file and
/// reach its encapsulated fragments.
struct TransferSyntaxTests {
    static let htj2kCases: [(TransferSyntax, String)] = [
        (.htj2kLossless, "1.2.840.10008.1.2.4.201"),
        (.htj2kLosslessRPCL, "1.2.840.10008.1.2.4.202"),
        (.htj2k, "1.2.840.10008.1.2.4.203")
    ]

    @Test(arguments: htj2kCases)
    func htj2kUIDRoundTripsThroughInit(transferSyntax: TransferSyntax, uid: String) {
        #expect(transferSyntax.uid == uid)
        #expect(TransferSyntax(uid: uid) == transferSyntax)
    }

    @Test(arguments: [TransferSyntax.htj2kLossless, .htj2kLosslessRPCL, .htj2k])
    func htj2kUsesEncapsulatedPixelData(transferSyntax: TransferSyntax) {
        #expect(transferSyntax.usesEncapsulatedPixelData)
    }

    @Test(arguments: [TransferSyntax.htj2kLossless, .htj2kLosslessRPCL, .htj2k])
    func htj2kDeclaringDatasetOpensAndExposesEncapsulatedFragments(transferSyntax: TransferSyntax) throws {
        // The fragment payload doesn't need to be a real HTJ2K codestream for
        // this test: it only checks that the file opens and the fragments
        // set at encoding time come back out, which is the part of the
        // contract that doesn't depend on ImageIO having an HTJ2K decoder.
        let fragment = Data([0xFF, 0x4F, 0xFF, 0x51, 0x00, 0x00])
        let data = imageFile(
            transferSyntaxUID: transferSyntax.uid,
            samplesPerPixel: 3,
            photometricInterpretation: .rgb,
            planarConfiguration: 0,
            rows: 1,
            columns: 2,
            bitsAllocated: 8,
            pixelDataElement: encapsulatedPixelData(fragments: [fragment])
        )

        let file = try DICOMFile(data: data)

        #expect(file.transferSyntax == transferSyntax)
        let fragments = try #require(file.dataset[.pixelData]?.encapsulatedFragments)
        #expect(fragments == [fragment])
    }

    @Test(arguments: [
        TransferSyntax.htj2kLossless, .htj2kLosslessRPCL, .htj2k,
        .rleLossless, .jpegBaseline, .jpegLossless, .jpegLosslessSV1,
        .jpegLSLossless, .jpegLSNearLossless, .jpeg2000Lossless, .jpeg2000,
        .implicitVRLittleEndian, .explicitVRLittleEndian, .explicitVRBigEndian,
        .deflatedExplicitVRLittleEndian
    ])
    func hasPixelDataDecoderIsTrueForEveryDecodableSyntax(transferSyntax: TransferSyntax) {
        #expect(transferSyntax.hasPixelDataDecoder)
    }

    @Test func hasPixelDataDecoderIsFalseForUnknownSyntax() {
        #expect(TransferSyntax(uid: "1.2.9999.not.a.real.syntax").hasPixelDataDecoder == false)
    }
}
