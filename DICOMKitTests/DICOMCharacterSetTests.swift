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

    // MARK: - ISO 2022 escape switching (single-byte extensions)

    @Test func escSwitchesG1ToLatin1ForTheRemainderOfARun() {
        let characterSet = DICOMCharacterSet(declaration: "ISO 2022 IR 6\\ISO 2022 IR 100")
        var bytes = Data("AB".utf8)
        bytes.append(contentsOf: [0x1B, 0x2D, 0x41]) // ESC - A: G1 = Latin-1
        bytes.append(0xE9)                            // é, GR byte (high bit set)
        bytes.append(contentsOf: Data("C".utf8))      // back to G0 (still ASCII)

        #expect(characterSet.decode(bytes) == "ABéC")
    }

    @Test func escSwitchesRomajiG0AndKatakanaG1() {
        let characterSet = DICOMCharacterSet(declaration: "ISO 2022 IR 6\\ISO 2022 IR 13")
        var bytes = Data("A".utf8)
        bytes.append(contentsOf: [0x1B, 0x28, 0x4A])       // ESC ( J: G0 = Japanese Romaji
        bytes.append(contentsOf: Data("B".utf8))
        bytes.append(contentsOf: [0x1B, 0x29, 0x49])       // ESC ) I: G1 = Japanese Katakana
        bytes.append(contentsOf: [0xB1, 0xB2, 0xB3])       // ｱｲｳ (JIS X 0201 katakana zone, GR)
        bytes.append(contentsOf: Data("C".utf8))

        #expect(characterSet.decode(bytes) == "ABｱｲｳC")
    }

    @Test func unrecognizedEscapeIsSkippedWithoutBreakingSurroundingText() {
        let characterSet = DICOMCharacterSet(declaration: "ISO 2022 IR 6\\ISO 2022 IR 100")
        var bytes = Data("A".utf8)
        bytes.append(contentsOf: [0x1B, 0x28, 0x5A]) // ESC ( Z: not a recognized designation
        bytes.append(contentsOf: Data("B".utf8))

        #expect(characterSet.decode(bytes) == "AB")
    }

    // MARK: - ISO 2022 escape switching (multi-byte extensions)

    @Test func escSwitchesG0ToJISX0208KanjiAndBackToASCII() {
        let characterSet = DICOMCharacterSet(declaration: "ISO 2022 IR 6\\ISO 2022 IR 87")
        var bytes = Data()
        bytes.append(contentsOf: [0x1B, 0x24, 0x42]) // ESC $ B: G0 = JIS X 0208 Kanji
        // JIS X 0208 row/cell bytes for "日本語" (verified independently via
        // Foundation's own ISO-2022-JP encoder, which emits exactly this
        // escape/payload/escape framing for that string).
        bytes.append(contentsOf: [0x46, 0x7C, 0x4B, 0x5C, 0x38, 0x6C])
        bytes.append(contentsOf: [0x1B, 0x28, 0x42]) // ESC ( B: back to ASCII
        bytes.append(contentsOf: Data("XY".utf8))

        #expect(characterSet.decode(bytes) == "日本語XY")
    }

    @Test func escSwitchesG1ToKoreanEUCPair() {
        let characterSet = DICOMCharacterSet(declaration: "ISO 2022 IR 149")
        var bytes = Data()
        bytes.append(contentsOf: [0x1B, 0x24, 0x29, 0x43]) // ESC $ ) C: G1 = KS X 1001 Korean
        // EUC-KR bytes for "한글" (verified independently via Foundation's
        // own EUC-KR encoding), already GR (high bit set).
        bytes.append(contentsOf: [0xC7, 0xD1, 0xB1, 0xDB])

        #expect(characterSet.decode(bytes) == "한글")
    }

    @Test func invalidMultiByteBytesFallBackRatherThanReturningNil() {
        let characterSet = DICOMCharacterSet(declaration: "ISO 2022 IR 6\\ISO 2022 IR 87")
        var bytes = Data()
        bytes.append(contentsOf: [0x1B, 0x24, 0x42]) // ESC $ B: G0 = JIS X 0208 Kanji
        bytes.append(0x41)                            // an incomplete (unpaired) double-byte code
        bytes.append(contentsOf: [0x1B, 0x28, 0x42]) // ESC ( B: back to ASCII
        bytes.append(contentsOf: Data("Z".utf8))

        // The lone 0x41 cannot form a JIS X 0208 pair, so ISO-2022-JP decoding
        // of that run fails; the decoder falls back to decoding the raw run
        // as ISO 8859-1 (which never fails) instead of losing the whole value.
        #expect(characterSet.decode(bytes) == "AZ")
    }
}
