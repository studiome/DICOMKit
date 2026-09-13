import Foundation
import Testing
@testable import DICOMKit

/// DICOM Specific Character Set `(0008,0005)` decoding (PS3.5 6.1.2.5).
///
/// The attribute is multi-valued: value 1 names the repertoire initially
/// active in G0, and values 2..n declare ISO 2022 code extensions reachable
/// by escape sequences within a value. Byte sequences below are built by
/// hand (or with Foundation's own encoder used only as an independent
/// reference to look up known code points) rather than through any encoder
/// this package provides, so the assertions exercise the decoder itself.
struct DICOMCharacterSetTests {
    @Test func isoIR100DecodesLatin1Byte() {
        let characterSet = DICOMCharacterSet(declaration: "ISO_IR 100")
        // 0xE9 is LATIN SMALL LETTER E WITH ACUTE in ISO 8859-1.
        #expect(characterSet.decode(Data([0xE9])) == "é")
    }

    @Test func isoIR192DecodesUTF8() {
        let characterSet = DICOMCharacterSet(declaration: "ISO_IR 192")
        #expect(characterSet.decode(Data("日本語".utf8)) == "日本語")
    }

    @Test func isoIR13DecodesHalfWidthKatakana() {
        let characterSet = DICOMCharacterSet(declaration: "ISO_IR 13")
        // 0xB1 0xB2 0xB3 are the JIS X 0201 katakana zone bytes for ｱｲｳ.
        #expect(characterSet.decode(Data([0xB1, 0xB2, 0xB3])) == "ｱｲｳ")
    }

    @Test func absentDeclarationYieldsASCII() {
        let characterSet = DICOMCharacterSet(declaration: nil)
        #expect(characterSet.codeElements == [.asciiDefault])
        #expect(characterSet.decode(Data("HELLO".utf8)) == "HELLO")
    }

    @Test func unrecognizedDefinedTermFallsBackToASCIIRatherThanNil() {
        let characterSet = DICOMCharacterSet(declaration: "SOME_UNKNOWN_TERM")
        #expect(characterSet.codeElements == [.asciiDefault])
        #expect(characterSet.decode(Data("HELLO".utf8)) == "HELLO")
    }

    /// Regression test: `ISO 2022 IR 6\ISO 2022 IR 87` is the standard
    /// Japanese declaration. Value 1 = "ISO 2022 IR 6" was not recognized by
    /// the previous four-case switch, so the whole declaration silently fell
    /// back to UTF-8 and Japanese Person Names failed to decode.
    @Test func japaneseDeclarationParsesBothCodeElements() {
        let characterSet = DICOMCharacterSet(declaration: "ISO 2022 IR 6\\ISO 2022 IR 87")
        #expect(characterSet.codeElements == [.asciiDefault, .japaneseKanji])
    }
}
