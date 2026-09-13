import Foundation
#if canImport(CoreFoundation)
import CoreFoundation
#endif

/// One repertoire ("code element" in PS3.5 terms) that a DICOM Specific
/// Character Set declaration can activate, either as the initial G0
/// repertoire (value 1) or as an ISO 2022 code extension reachable by an
/// escape sequence (values 2..n).
public enum DICOMCodeElement: Sendable, Equatable, Hashable {
    /// ISO-IR 6, the DICOM default character repertoire (7-bit ASCII).
    case asciiDefault
    /// ISO-IR 100 (Latin alphabet No. 1 / ISO 8859-1).
    case latin1
    /// ISO-IR 101 (Latin alphabet No. 2 / ISO 8859-2).
    case latin2
    /// ISO-IR 109 (Latin alphabet No. 3 / ISO 8859-3).
    case latin3
    /// ISO-IR 110 (Latin alphabet No. 4 / ISO 8859-4).
    case latin4
    /// ISO-IR 144 (Cyrillic / ISO 8859-5).
    case cyrillic
    /// ISO-IR 127 (Arabic / ISO 8859-6).
    case arabic
    /// ISO-IR 126 (Greek / ISO 8859-7).
    case greek
    /// ISO-IR 138 (Hebrew / ISO 8859-8).
    case hebrew
    /// ISO-IR 148 (Latin alphabet No. 5 / ISO 8859-9).
    case latin5
    /// ISO-IR 166 (Thai / TIS 620-2533).
    case thai
    /// ISO-IR 14 (Japanese Romaji), only reachable as a G0 code extension.
    case japaneseRomaji
    /// ISO-IR 13 (Japanese Katakana).
    case japaneseKatakana
    /// ISO-IR 87 (Japanese Kanji, JIS X 0208), a multi-byte code extension.
    case japaneseKanji
    /// ISO-IR 159 (Japanese Supplementary Kanji, JIS X 0212), a multi-byte code extension.
    case japaneseSupplementaryKanji
    /// ISO-IR 149 (Korean, KS X 1001), a multi-byte code extension.
    case korean
    /// ISO-IR 58 (Simplified Chinese, GB2312), a multi-byte code extension.
    case simplifiedChinese
    /// ISO-IR 192 (Unicode UTF-8).
    case utf8
    /// GB18030 / GBK.
    case gb18030

    /// Whether this repertoire is a multi-byte ISO 2022 code extension
    /// (Japanese Kanji/Supplementary Kanji, Korean, Simplified Chinese).
    /// These are only ever reached through an escape sequence inside a
    /// multi-valued declaration, never decoded as a whole buffer directly.
    var isMultiByteCodeExtension: Bool {
        switch self {
        case .japaneseKanji, .japaneseSupplementaryKanji, .korean, .simplifiedChinese: return true
        default: return false
        }
    }

    /// The Foundation encoding used to decode a contiguous buffer in this
    /// repertoire, for the single-byte (or UTF-8/GB18030) repertoires that
    /// Foundation can decode directly. `nil` for the multi-byte code
    /// extensions, which are decoded per-run by the ISO 2022 escape state
    /// machine instead (see `DICOMCharacterSet.decode(_:)`).
    var wholeBufferEncoding: String.Encoding? {
        switch self {
        case .asciiDefault, .japaneseRomaji: return .ascii
        case .latin1: return .isoLatin1
        case .latin2: return .isoLatin2
        case .latin3: return Self.encoding(Self.cfStringEncodingISOLatin3)
        case .latin4: return Self.encoding(Self.cfStringEncodingISOLatin4)
        case .cyrillic: return Self.encoding(Self.cfStringEncodingISOLatinCyrillic)
        case .arabic: return Self.encoding(Self.cfStringEncodingISOLatinArabic)
        case .greek: return Self.encoding(Self.cfStringEncodingISOLatinGreek)
        case .hebrew: return Self.encoding(Self.cfStringEncodingISOLatinHebrew)
        case .latin5: return Self.encoding(Self.cfStringEncodingISOLatin5)
        case .thai: return Self.encoding(Self.cfStringEncodingISOLatinThai)
        case .japaneseKatakana: return .shiftJIS
        case .utf8: return .utf8
        case .gb18030: return Self.encoding(Self.cfStringEncodingGB18030_2000)
        case .japaneseKanji, .japaneseSupplementaryKanji, .korean, .simplifiedChinese: return nil
        }
    }

    // The Swift overlay for CoreFoundation does not import these `CFStringEncodingExt.h`
    // constants as top-level `kCFStringEncoding...` globals (they are grouped into an
    // anonymous C enum, which the importer instead surfaces piecemeal as
    // `CFStringEncodings` cases with inconsistent spellings). Their values are stable
    // ABI constants documented in `CFStringEncodingExt.h`, so they are reproduced here
    // directly rather than depending on the importer's naming for each one.
    fileprivate static let cfStringEncodingISOLatin3: CFStringEncoding = 0x0203
    fileprivate static let cfStringEncodingISOLatin4: CFStringEncoding = 0x0204
    fileprivate static let cfStringEncodingISOLatinCyrillic: CFStringEncoding = 0x0205
    fileprivate static let cfStringEncodingISOLatinArabic: CFStringEncoding = 0x0206
    fileprivate static let cfStringEncodingISOLatinGreek: CFStringEncoding = 0x0207
    fileprivate static let cfStringEncodingISOLatinHebrew: CFStringEncoding = 0x0208
    fileprivate static let cfStringEncodingISOLatin5: CFStringEncoding = 0x0209
    fileprivate static let cfStringEncodingISOLatinThai: CFStringEncoding = 0x020B
    fileprivate static let cfStringEncodingGB18030_2000: CFStringEncoding = 0x0632

    fileprivate static func encoding(_ cfEncoding: CFStringEncoding) -> String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
    }
}

/// A DICOM Specific Character Set `(0008,0005)` declaration (PS3.5 6.1.2.5).
///
/// The attribute is multi-valued: value 1 names the repertoire initially
/// active in the G0 code element register, and values 2..n declare ISO 2022
/// code extensions that a value's escape sequences may switch to. Modeling
/// the full declaration (rather than only its first value, as a prior
/// implementation did) is required to decode values that use extensions —
/// most notably the standard Japanese declaration
/// `ISO 2022 IR 6\ISO 2022 IR 87`.
public struct DICOMCharacterSet: Sendable, Equatable {
    /// The declared code elements, in declaration order. Always non-empty.
    public let codeElements: [DICOMCodeElement]

    /// Parses the backslash-separated Defined Terms of a Specific Character
    /// Set declaration.
    ///
    /// An absent, empty, or wholly unrecognized declaration yields
    /// `[.asciiDefault]` (ISO-IR 6, the DICOM default repertoire) so callers
    /// always get a usable character set rather than having to handle `nil`.
    public init(declaration: String?) {
        guard let declaration, !declaration.isEmpty else {
            codeElements = [.asciiDefault]
            return
        }
        let terms = declaration.split(separator: "\\", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let parsed = terms.compactMap(Self.codeElement(forDefinedTerm:))
        codeElements = parsed.isEmpty ? [.asciiDefault] : parsed
    }

    /// UTF-8 (ISO-IR 192).
    public static let utf8 = DICOMCharacterSet(declaration: "ISO_IR 192")
    /// The DICOM default character repertoire (ISO-IR 6 / ASCII).
    public static let `default` = DICOMCharacterSet(declaration: nil)

    private static func codeElement(forDefinedTerm term: String) -> DICOMCodeElement? {
        switch term {
        case "": return .asciiDefault

        // Without code extensions (single-valued declarations).
        case "ISO_IR 100": return .latin1
        case "ISO_IR 101": return .latin2
        case "ISO_IR 109": return .latin3
        case "ISO_IR 110": return .latin4
        case "ISO_IR 144": return .cyrillic
        case "ISO_IR 127": return .arabic
        case "ISO_IR 126": return .greek
        case "ISO_IR 138": return .hebrew
        case "ISO_IR 148": return .latin5
        case "ISO_IR 166": return .thai
        case "ISO_IR 13": return .japaneseKatakana
        case "ISO_IR 192": return .utf8
        case "GB18030", "GBK": return .gb18030

        // With code extensions.
        case "ISO 2022 IR 6": return .asciiDefault
        case "ISO 2022 IR 100": return .latin1
        case "ISO 2022 IR 101": return .latin2
        case "ISO 2022 IR 109": return .latin3
        case "ISO 2022 IR 110": return .latin4
        case "ISO 2022 IR 144": return .cyrillic
        case "ISO 2022 IR 127": return .arabic
        case "ISO 2022 IR 126": return .greek
        case "ISO 2022 IR 138": return .hebrew
        case "ISO 2022 IR 148": return .latin5
        case "ISO 2022 IR 166": return .thai
        case "ISO 2022 IR 13": return .japaneseKatakana
        case "ISO 2022 IR 87": return .japaneseKanji
        case "ISO 2022 IR 159": return .japaneseSupplementaryKanji
        case "ISO 2022 IR 149": return .korean
        case "ISO 2022 IR 58": return .simplifiedChinese

        default: return nil
        }
    }

    /// Decodes raw bytes using this declaration.
    ///
    /// When exactly one code element is declared and it isn't a multi-byte
    /// code extension, the whole buffer is decoded directly with that
    /// repertoire's encoding — the common case, and one that needs no ISO
    /// 2022 escape processing at all. Declarations with code extensions
    /// (more than one code element, or a lone multi-byte one) are decoded by
    /// walking escape sequences; see the ISO 2022 state machine added
    /// alongside that support.
    ///
    /// If a repertoire's encoding is unavailable on the current platform, or
    /// decoding otherwise fails, this falls back to ISO 8859-1 (Latin-1),
    /// which can represent every byte value and therefore never fails to
    /// produce a `String`. A mojibake string is more useful to a viewer than
    /// a `nil` that erases an entire Patient Name.
    public func decode(_ data: Data) -> String? {
        if codeElements.count == 1, !codeElements[0].isMultiByteCodeExtension {
            return Self.decodeWholeBuffer(data, repertoire: codeElements[0])
        }
        return decodeWithCodeExtensions(data)
    }

    private static func decodeWholeBuffer(_ data: Data, repertoire: DICOMCodeElement) -> String? {
        if let encoding = repertoire.wholeBufferEncoding, let value = String(data: data, encoding: encoding) {
            return value
        }
        return String(data: data, encoding: .isoLatin1)
    }

    /// The G0/G1 code element register an ISO 2022 escape sequence switches.
    private enum EscapeRegister { case g0, g1 }

    /// ISO 2022 escape sequences DICOM PS3.5 Table 6.1-2 defines for
    /// switching the active G0/G1 repertoire, keyed by the bytes that follow
    /// ESC (0x1B). Recognizing a new sequence is just adding a table entry;
    /// the scanner in `decodeWithCodeExtensions` finds each sequence's
    /// length itself from the general ISO/IEC 2022 escape grammar (ESC, then
    /// intermediate bytes 0x20–0x2F, then a final byte 0x30–0x7E) rather
    /// than this table hardcoding lengths.
    private static let escapeActions: [[UInt8]: (EscapeRegister, DICOMCodeElement)] = [
        [0x28, 0x42]: (.g0, .asciiDefault),      // ESC ( B
        [0x28, 0x4A]: (.g0, .japaneseRomaji),    // ESC ( J
        [0x29, 0x49]: (.g1, .japaneseKatakana),  // ESC ) I
        [0x2D, 0x41]: (.g1, .latin1),            // ESC - A
        [0x2D, 0x42]: (.g1, .latin2),            // ESC - B
        [0x2D, 0x43]: (.g1, .latin3),            // ESC - C
        [0x2D, 0x44]: (.g1, .latin4),            // ESC - D
        [0x2D, 0x46]: (.g1, .greek),             // ESC - F
        [0x2D, 0x47]: (.g1, .arabic),            // ESC - G
        [0x2D, 0x48]: (.g1, .hebrew),            // ESC - H
        [0x2D, 0x4C]: (.g1, .cyrillic),          // ESC - L
        [0x2D, 0x4D]: (.g1, .latin5),            // ESC - M
        [0x2D, 0x54]: (.g1, .thai),              // ESC - T

        // Multi-byte code extensions.
        [0x24, 0x42]: (.g0, .japaneseKanji),                    // ESC $ B
        [0x24, 0x28, 0x44]: (.g0, .japaneseSupplementaryKanji), // ESC $ ( D
        [0x24, 0x29, 0x43]: (.g1, .korean),                     // ESC $ ) C
        [0x24, 0x29, 0x41]: (.g1, .simplifiedChinese)           // ESC $ ) A
    ]

    /// Decodes a declaration with ISO 2022 code extensions by walking its
    /// bytes, maintaining G0 (initially the declaration's value 1, or ASCII
    /// when value 1 is empty) and G1 (initially undesignated) repertoires.
    ///
    /// Per the DICOM restriction of ISO/IEC 2022 to two registers (PS3.5
    /// 6.1.2.4 Note), a byte's register is determined by its high bit: clear
    /// selects G0, set selects G1. Consecutive bytes that share a register
    /// are accumulated into one run and decoded with one call, so a
    /// multi-byte repertoire's sequences are never split byte-by-byte. A
    /// high-bit byte before any G1 designation falls back to decoding under
    /// G0, since that should not occur in a conformant stream.
    ///
    /// An unrecognized escape sequence is skipped — its own bytes never join
    /// a run and are never emitted as text — but does not abort the decode;
    /// the surrounding bytes are still decoded normally. This is safer than
    /// guessing at an unknown extension's semantics or corrupting the run
    /// that follows it.
    private func decodeWithCodeExtensions(_ data: Data) -> String? {
        var g0 = codeElements.first ?? .asciiDefault
        var g1: DICOMCodeElement?
        var result = ""
        var runBytes: [UInt8] = []
        var runRegister: EscapeRegister?

        func flushRun() {
            guard !runBytes.isEmpty else { return }
            let repertoire = (runRegister == .g1) ? (g1 ?? g0) : g0
            result += Self.decodeRun(Data(runBytes), repertoire: repertoire) ?? ""
            runBytes.removeAll(keepingCapacity: true)
        }

        let bytes = [UInt8](data)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            guard byte == 0x1B else {
                let register: EscapeRegister = (byte & 0x80) != 0 ? .g1 : .g0
                if register != runRegister { flushRun(); runRegister = register }
                runBytes.append(byte)
                index += 1
                continue
            }

            // ISO/IEC 2022 escape grammar: ESC, intermediate bytes (0x20–0x2F),
            // then one final byte (0x30–0x7E) that terminates the sequence.
            var scan = index + 1
            while scan < bytes.count, (0x20...0x2F).contains(bytes[scan]) { scan += 1 }
            guard scan < bytes.count, (0x30...0x7E).contains(bytes[scan]) else {
                // Truncated escape sequence at the end of the buffer: nothing
                // recoverable follows, so stop here.
                break
            }
            let sequence = Array(bytes[(index + 1)...scan])
            index = scan + 1
            if let (register, element) = Self.escapeActions[sequence] {
                flushRun()
                switch register {
                case .g0: g0 = element
                case .g1: g1 = element
                }
            }
            // else: unrecognized escape — already skipped by advancing `index`.
        }
        flushRun()
        return result
    }

    /// Decodes one contiguous run of bytes that all belong to the same G0/G1
    /// repertoire. For single-byte repertoires (and UTF-8/GB18030) this is
    /// the same whole-buffer decode as the non-extension path; multi-byte
    /// code extensions are decoded by `decodeMultiByteRun`, falling back to
    /// ISO 8859-1 like every other path here when that fails.
    private static func decodeRun(_ data: Data, repertoire: DICOMCodeElement) -> String? {
        guard repertoire.isMultiByteCodeExtension else {
            return decodeWholeBuffer(data, repertoire: repertoire)
        }
        if let decoded = decodeMultiByteRun(data, repertoire: repertoire) { return decoded }
        return String(data: data, encoding: .isoLatin1)
    }

    /// Decodes one run of a multi-byte ISO 2022 code extension by handing it
    /// to Foundation in a form Foundation already understands, rather than
    /// shipping and maintaining JIS X 0208/0212, KS X 1001, or GB2312
    /// code-page tables in this package.
    ///
    /// Japanese Kanji and Supplementary Kanji runs are re-wrapped as a
    /// self-contained ISO-2022-JP(-2) document: the same designation escape
    /// that selected the repertoire, the run bytes verbatim, then `ESC ( B`
    /// to return to ASCII — exactly the framing `String.Encoding.iso2022JP`
    /// (or its JIS X 0212 superset) expects, since DICOM's escape framing
    /// for these repertoires already matches ISO-2022-JP's.
    ///
    /// Korean and Simplified Chinese runs arrive as GR bytes (DICOM invokes
    /// G1 via the high bit rather than a shift code), which is exactly what
    /// EUC-KR/EUC-CN expect. Since a run is classified by that same high
    /// bit, every byte routed here already has it set; each byte is OR'd
    /// with 0x80 anyway as a defensive no-op, in case a future caller ever
    /// hands this a run assembled some other way.
    private static func decodeMultiByteRun(_ data: Data, repertoire: DICOMCodeElement) -> String? {
        switch repertoire {
        case .japaneseKanji:
            return decodeISO2022JPRun(data, designation: [0x1B, 0x24, 0x42], encoding: .iso2022JP)
        case .japaneseSupplementaryKanji:
            return decodeISO2022JPRun(data, designation: [0x1B, 0x24, 0x28, 0x44], encoding: DICOMCodeElement.encoding(cfStringEncodingISO2022JP2))
                ?? decodeISO2022JPRun(data, designation: [0x1B, 0x24, 0x28, 0x44], encoding: .iso2022JP)
        case .korean:
            return decodeEUCRun(data, encoding: DICOMCodeElement.encoding(cfStringEncodingEUC_KR))
        case .simplifiedChinese:
            return decodeEUCRun(data, encoding: DICOMCodeElement.encoding(cfStringEncodingEUC_CN))
        default:
            return nil
        }
    }

    private static func decodeISO2022JPRun(_ data: Data, designation: [UInt8], encoding: String.Encoding) -> String? {
        var wrapped = Data(designation)
        wrapped.append(data)
        wrapped.append(contentsOf: [0x1B, 0x28, 0x42]) // ESC ( B: back to ASCII
        return String(data: wrapped, encoding: encoding)
    }

    private static func decodeEUCRun(_ data: Data, encoding: String.Encoding) -> String? {
        String(data: Data(data.map { $0 | 0x80 }), encoding: encoding)
    }

    fileprivate static let cfStringEncodingISO2022JP2: CFStringEncoding = 0x0821
    fileprivate static let cfStringEncodingEUC_KR: CFStringEncoding = 0x0940
    fileprivate static let cfStringEncodingEUC_CN: CFStringEncoding = 0x0930
}
