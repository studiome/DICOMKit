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
        // JIS X 0208 row/cell bytes for "山田" (verified independently via
        // Foundation's own ISO-2022-JP encoder, which emits exactly this
        // escape/payload/escape framing for that string). Chosen instead of
        // e.g. "日本語" because none of its bytes equal the `\`/`=`/`^`
        // delimiter values that reset escape state (see the delimiter tests
        // below) — PS3.5 leaves it to the creator of a multi-byte-encoded
        // value to avoid that collision in the first place.
        bytes.append(contentsOf: [0x3B, 0x33, 0x45, 0x44])
        bytes.append(contentsOf: [0x1B, 0x28, 0x42]) // ESC ( B: back to ASCII
        bytes.append(contentsOf: Data("XY".utf8))

        #expect(characterSet.decode(bytes) == "山田XY")
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

    // MARK: - Delimiter state reset (PS3.5 6.1.2.5.3) and Person Names

    /// JIS X 0208 row/cell bytes for "田中" (verified independently via
    /// Foundation's ISO-2022-JP encoder). Deliberately chosen because none of
    /// its bytes collide with the `\`, `=`, or `^` delimiter values, unlike
    /// the "日本語" fixture used elsewhere in this file.
    private static let tanakaKanjiBytes: [UInt8] = [0x45, 0x44, 0x43, 0x66]

    @Test func personNameDecodesASCIIAlphabeticAndEscapedIdeographicComponents() {
        var value = Data("Tanaka".utf8)
        value.append(0x3D) // '=' component-group delimiter
        value.append(contentsOf: [0x1B, 0x24, 0x42]) // ESC $ B: G0 = JIS X 0208 Kanji
        value.append(contentsOf: Self.tanakaKanjiBytes)
        value.append(contentsOf: [0x1B, 0x28, 0x42]) // ESC ( B: back to ASCII

        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .specificCharacterSet, vr: .CS, value: Data("ISO 2022 IR 6\\ISO 2022 IR 87".utf8)),
            DICOMElement(tag: .patientName, vr: .PN, value: value)
        ])

        let name = dataset.personNameValue(for: .patientName)
        #expect(name?.alphabetic == "Tanaka")
        #expect(name?.ideographic == "田中")
    }

    @Test func twoValuedAttributeDecodesBothValuesWhenOnlyTheSecondEscapes() {
        let characterSet = DICOMCharacterSet(declaration: "ISO 2022 IR 6\\ISO 2022 IR 87")
        var value = Data("AB".utf8)
        value.append(0x5C) // '\' value delimiter
        value.append(contentsOf: [0x1B, 0x24, 0x42])
        value.append(contentsOf: Self.tanakaKanjiBytes)
        value.append(contentsOf: [0x1B, 0x28, 0x42])

        let element = DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x0080), vr: .LO, value: value)
        #expect(element.stringValues(characterSet: characterSet) == ["AB", "田中"])
    }

    @Test func escapeStateDoesNotLeakAcrossAValueDelimiter() {
        let characterSet = DICOMCharacterSet(declaration: "ISO 2022 IR 6\\ISO 2022 IR 87")
        var value = Data()
        value.append(contentsOf: [0x1B, 0x24, 0x42]) // switch to Kanji, deliberately not switched back
        value.append(contentsOf: Self.tanakaKanjiBytes)
        value.append(0x5C) // '\' value delimiter: must reset G0 back to ASCII
        value.append(contentsOf: Data("CD".utf8))

        let element = DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x0080), vr: .LO, value: value)
        #expect(element.stringValues(characterSet: characterSet) == ["田中", "CD"])
    }

    // MARK: - Character set inheritance in sequence items (PS3.5 7.5.3)

    /// JIS X 0208 row/cell bytes for "山田" (see `escSwitchesG0ToJISX0208KanjiAndBackToASCII`).
    private static let yamadaKanjiBytes: [UInt8] = [0x3B, 0x33, 0x45, 0x44]

    @Test func sequenceItemInheritsParentCharacterSetWhenItDeclaresNone() {
        var value = Data()
        value.append(contentsOf: [0x1B, 0x24, 0x42])
        value.append(contentsOf: Self.yamadaKanjiBytes)
        value.append(contentsOf: [0x1B, 0x28, 0x42])

        let parent = DICOMDataset(elements: [
            DICOMElement(tag: .specificCharacterSet, vr: .CS, value: Data("ISO 2022 IR 6\\ISO 2022 IR 87".utf8))
        ])
        let item = DICOMDataset(elements: [
            DICOMElement(tag: .lutExplanation, vr: .LO, value: value)
        ])

        let inherited = item.characterSet(inheriting: parent.characterSet)
        #expect(inherited.codeElements == [.asciiDefault, .japaneseKanji])
        #expect(item.stringValue(for: .lutExplanation, inheriting: parent.characterSet) == "山田")
    }

    @Test func sequenceItemOwnCharacterSetOverridesParent() {
        let parent = DICOMDataset(elements: [
            DICOMElement(tag: .specificCharacterSet, vr: .CS, value: Data("ISO_IR 100".utf8))
        ])
        let item = DICOMDataset(elements: [
            DICOMElement(tag: .specificCharacterSet, vr: .CS, value: Data("ISO_IR 192".utf8)),
            DICOMElement(tag: .lutExplanation, vr: .LO, value: Data("日本語".utf8))
        ])

        #expect(item.characterSet(inheriting: parent.characterSet).codeElements == [.utf8])
        #expect(item.stringValue(for: .lutExplanation, inheriting: parent.characterSet) == "日本語")
    }

    @Test func nestedItemTwoLevelsDeepInheritsFromNearestDeclaringAncestor() {
        let grandparent = DICOMDataset(elements: [
            DICOMElement(tag: .specificCharacterSet, vr: .CS, value: Data("ISO_IR 100".utf8))
        ])
        // Neither the parent nor the child declares its own Specific
        // Character Set, so both must resolve back to the grandparent's.
        let parent = DICOMDataset(elements: [])
        let child = DICOMDataset(elements: [
            DICOMElement(tag: .lutExplanation, vr: .LO, value: Data([0xE9])) // é in ISO 8859-1
        ])

        let parentCharacterSet = parent.characterSet(inheriting: grandparent.characterSet)
        let childCharacterSet = child.characterSet(inheriting: parentCharacterSet)

        #expect(childCharacterSet.codeElements == [.latin1])
        #expect(child.stringValue(for: .lutExplanation, inheriting: parentCharacterSet) == "é")
    }

    @Test func dicomFileModalityLUTExplanationInheritsDatasetCharacterSet() throws {
        var explanationValue = Data()
        explanationValue.append(contentsOf: [0x1B, 0x24, 0x42])
        explanationValue.append(contentsOf: Self.yamadaKanjiBytes)
        explanationValue.append(contentsOf: [0x1B, 0x28, 0x42])

        // The LUT Sequence item declares no Specific Character Set of its
        // own, so DICOMFile must inherit the main dataset's declaration to
        // decode LUT Explanation — exercising the audited call site in
        // `DICOMFile.makeModalityLUT()`.
        let lutItem = DICOMDataset(elements: [
            DICOMElement(tag: .lutDescriptor, vr: .US, value: uint16(3) + uint16(0) + uint16(16)),
            DICOMElement(tag: .lutData, vr: .OW, value: uint16(10) + uint16(20) + uint16(30)),
            DICOMElement(tag: .lutExplanation, vr: .LO, value: explanationValue)
        ])
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .specificCharacterSet, vr: .CS, value: Data("ISO 2022 IR 6\\ISO 2022 IR 87".utf8)),
            DICOMElement(tag: .samplesPerPixel, vr: .US, value: uint16(1)),
            DICOMElement(tag: .photometricInterpretation, vr: .CS, value: Data("MONOCHROME2".utf8)),
            DICOMElement(tag: .rows, vr: .US, value: uint16(1)),
            DICOMElement(tag: .columns, vr: .US, value: uint16(1)),
            DICOMElement(tag: .bitsAllocated, vr: .US, value: uint16(16)),
            DICOMElement(tag: DICOMTag(group: 0x0028, element: 0x3000), vr: .SQ, value: Data(), sequenceItems: [lutItem]),
            DICOMElement(tag: .pixelData, vr: .OW, value: Data([0, 0]))
        ])

        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))
        #expect(file.pixelDataFrames?.first?.modalityLUT?.explanation == "山田")
    }
}
