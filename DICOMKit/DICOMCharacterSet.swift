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

    private static func encoding(_ cfEncoding: CFStringEncoding) -> String.Encoding {
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

    /// Placeholder for the ISO 2022 escape-sequence state machine.
    ///
    /// Declarations with code extensions are decoded byte-run-by-byte,
    /// switching G0/G1 repertoires on recognized escape sequences. Until
    /// that state machine is implemented, fall back to decoding the whole
    /// buffer with the initial (value 1) repertoire, ignoring any escapes —
    /// better than returning `nil`, though it does not yet handle switches.
    private func decodeWithCodeExtensions(_ data: Data) -> String? {
        Self.decodeWholeBuffer(data, repertoire: codeElements[0])
    }
}
