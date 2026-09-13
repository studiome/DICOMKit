import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import DICOMKit

/// Decoding behavior for the HTJ2K transfer syntaxes.
///
/// DICOMKit has no HTJ2K encoder and no real HTJ2K fixture, so these tests
/// cannot verify that a genuine HT-coded codestream renders. What they do
/// verify is the contract that matters even without a fixture: a file
/// declaring HTJ2K always opens, and when the codestream can't be decoded
/// (garbage bytes, or — on a platform without HTJ2K support — a real one)
/// `DICOMFile(data:)` still succeeds and `pixelDataFrames` reports `nil`
/// rather than throwing.
struct HTJ2KTests {
    @Test(arguments: [TransferSyntax.htj2kLossless, .htj2kLosslessRPCL, .htj2k])
    func htj2kFileWithUndecodablePayloadOpensWithNilFrames(transferSyntax: TransferSyntax) throws {
        // Not a JPEG 2000/HTJ2K codestream at all, just arbitrary bytes — this
        // stands in for "ImageIO rejects this stream" however that happens,
        // whether because it's not a codestream ImageIO recognizes or
        // because it uses an HT block coder ImageIO doesn't support.
        let undecodablePayload = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07])
        let data = imageFile(
            transferSyntaxUID: transferSyntax.uid,
            samplesPerPixel: 3,
            photometricInterpretation: .rgb,
            planarConfiguration: 0,
            rows: 1,
            columns: 2,
            bitsAllocated: 8,
            pixelDataElement: encapsulatedPixelData(fragments: [undecodablePayload])
        )

        // The initializer must not throw: an undecodable frame is a decode
        // failure, not a parse failure.
        let file = try DICOMFile(data: data)

        #expect(file.transferSyntax == transferSyntax)
        #expect(file.pixelDataFrames == nil)
    }

    /// Reports what this platform's ImageIO advertises for JPEG 2000, as the
    /// closest available proxy for HTJ2K decodability.
    ///
    /// This intentionally does not assert on the outcome. There is no
    /// distinct UTI for HTJ2K — PS3.5 Annex A.4.4 describes it as a JPEG 2000
    /// codestream that swaps in a different (FBCOT) block coder, so DICOMKit
    /// routes it through the exact same `CGImageSourceCreateWithData` /
    /// `public.jpeg-2000` path as `.jpeg2000Lossless` / `.jpeg2000` (see
    /// `DICOMFile.pixelDataFrames`). Whether `public.jpeg-2000` is listed
    /// here is necessary but not sufficient for HTJ2K to actually decode:
    /// ImageIO could open the container and still reject the HT-coded
    /// blocks inside a real HTJ2K stream. Without an HTJ2K encoder or a
    /// fixture built from one, this suite can't tell the difference — so it
    /// only reports what it observes, rather than asserting a
    /// platform-specific result that would turn red the day a platform
    /// gains (or an intermediate OS temporarily drops) HTJ2K support.
    @Test func reportsImageIOJPEG2000CapabilityAsHTJ2KProxy() {
        let identifiers = (CGImageSourceCopyTypeIdentifiers() as? [String]) ?? []
        let supportsJPEG2000Container = identifiers.contains("public.jpeg-2000")
        // Surfaced as a diagnostic, not an assertion — see the doc comment.
        print(
            "[HTJ2K capability probe] ImageIO CGImageSourceCopyTypeIdentifiers() "
            + "contains \"public.jpeg-2000\": \(supportsJPEG2000Container). "
            + "This says whether the JPEG 2000 container/codestream path DICOMKit "
            + "routes HTJ2K through exists on this platform; it does not confirm "
            + "that platform can decode HT-coded blocks specifically."
        )
    }
}
