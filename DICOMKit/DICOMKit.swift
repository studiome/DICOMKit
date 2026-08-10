import Foundation
import CoreGraphics

/// A DICOM data-element identifier consisting of a group and element number.
public struct DICOMTag: Hashable, Sendable, CustomStringConvertible {
    /// The 16-bit DICOM group number.
    public let group: UInt16
    /// The 16-bit DICOM element number.
    public let element: UInt16

    /// Creates a tag from its group and element numbers.
    public init(group: UInt16, element: UInt16) {
        self.group = group
        self.element = element
    }

    /// The canonical hexadecimal representation, for example `(0010,0010)`.
    public var description: String { String(format: "(%04X,%04X)", group, element) }

    /// Transfer Syntax UID `(0002,0010)` in File Meta Information.
    public static let transferSyntaxUID = DICOMTag(group: 0x0002, element: 0x0010)
    /// Patient's Name `(0010,0010)`.
    public static let patientName = DICOMTag(group: 0x0010, element: 0x0010)
    /// Rows `(0028,0010)`.
    public static let rows = DICOMTag(group: 0x0028, element: 0x0010)
    /// Columns `(0028,0011)`.
    public static let columns = DICOMTag(group: 0x0028, element: 0x0011)
    /// Pixel Data `(7FE0,0010)`.
    public static let pixelData = DICOMTag(group: 0x7FE0, element: 0x0010)
    /// Samples per Pixel `(0028,0002)`.
    public static let samplesPerPixel = DICOMTag(group: 0x0028, element: 0x0002)
    /// Photometric Interpretation `(0028,0004)`.
    public static let photometricInterpretation = DICOMTag(group: 0x0028, element: 0x0004)
    /// Planar Configuration `(0028,0006)`.
    public static let planarConfiguration = DICOMTag(group: 0x0028, element: 0x0006)
    /// Bits Allocated `(0028,0100)`.
    public static let bitsAllocated = DICOMTag(group: 0x0028, element: 0x0100)
    /// Bits Stored `(0028,0101)`.
    public static let bitsStored = DICOMTag(group: 0x0028, element: 0x0101)
    /// High Bit `(0028,0102)`.
    public static let highBit = DICOMTag(group: 0x0028, element: 0x0102)
    /// Pixel Representation `(0028,0103)`: `0` for unsigned integer, `1` for
    /// 2's complement signed integer.
    public static let pixelRepresentation = DICOMTag(group: 0x0028, element: 0x0103)
    /// Window Center `(0028,1050)`.
    public static let windowCenter = DICOMTag(group: 0x0028, element: 0x1050)
    /// Window Width `(0028,1051)`.
    public static let windowWidth = DICOMTag(group: 0x0028, element: 0x1051)
    /// Rescale Intercept `(0028,1052)`.
    public static let rescaleIntercept = DICOMTag(group: 0x0028, element: 0x1052)
    /// Rescale Slope `(0028,1053)`.
    public static let rescaleSlope = DICOMTag(group: 0x0028, element: 0x1053)
    /// Referenced Study Sequence `(0008,1110)`.
    public static let referencedStudySequence = DICOMTag(group: 0x0008, element: 0x1110)
    /// Referenced SOP Class UID `(0008,1150)`.
    public static let referencedSOPClassUID = DICOMTag(group: 0x0008, element: 0x1150)
}

/// A DICOM Value Representation (VR).
///
/// The raw value of each case is the two-letter code defined by DICOM PS3.5.
public enum DICOMVR: String, Sendable, CaseIterable {
    case AE, AS, AT, CS, DA, DS, DT, FD, FL, IS, LO, LT, OB, OD, OF, OL, OV, OW
    case PN, SH, SL, SQ, SS, ST, SV, TM, UC, UI, UL, UN, UR, US, UT, UV

    var uses32BitLength: Bool {
        switch self {
        case .OB, .OD, .OF, .OL, .OV, .OW, .SQ, .SV, .UC, .UN, .UR, .UT, .UV:
            true
        default:
            false
        }
    }
}

/// A DICOM data element and its decoded structural information.
public struct DICOMElement: Sendable {
    /// The element's DICOM tag.
    public let tag: DICOMTag
    /// The element's Value Representation.
    public let vr: DICOMVR
    /// The raw encoded value for non-sequence elements.
    ///
    /// This value is empty for elements whose VR is ``DICOMVR/SQ``.
    public let value: Data
    /// The datasets contained by a sequence element, or `nil` for a non-sequence element.
    public let sequenceItems: [DICOMDataset]?

    /// Creates an element from its tag, VR, raw value, and optional sequence items.
    public init(tag: DICOMTag, vr: DICOMVR, value: Data, sequenceItems: [DICOMDataset]? = nil) {
        self.tag = tag
        self.vr = vr
        self.value = value
        self.sequenceItems = sequenceItems
    }

    /// The UTF-8 string value with DICOM space and NUL padding removed.
    ///
    /// Returns `nil` for sequence elements or values that aren't valid UTF-8.
    public var stringValue: String? {
        guard sequenceItems == nil else { return nil }
        var trimmedValue = value
        while let last = trimmedValue.last, last == 0 || last == 0x20 {
            trimmedValue.removeLast()
        }
        return String(data: trimmedValue, encoding: .utf8)
    }

    /// The first 16-bit unsigned little-endian value, if the value contains one.
    public var uint16Value: UInt16? {
        guard value.count >= 2 else { return nil }
        return UInt16(value[value.startIndex]) | (UInt16(value[value.startIndex + 1]) << 8)
    }

    /// The first 16-bit signed little-endian value, if the value contains one.
    ///
    /// Intended for the `SS` VR.
    public var int16Value: Int16? {
        guard let bitPattern = uint16Value else { return nil }
        return Int16(bitPattern: bitPattern)
    }

    /// The first numeric value parsed from a string-encoded numeric VR such as
    /// `DS` or `IS`.
    ///
    /// DICOM allows `DS` (Decimal String) and `IS` (Integer String) values to
    /// contain multiple backslash-separated values; only the first value is
    /// returned. Surrounding whitespace is trimmed. Returns `nil` if the value
    /// is empty, isn't valid UTF-8, or the first component can't be parsed as
    /// a `Double`.
    public var doubleValue: Double? {
        guard let stringValue else { return nil }
        let firstComponent = stringValue.split(separator: "\\", maxSplits: 1, omittingEmptySubsequences: false)[0]
        return Double(firstComponent.trimmingCharacters(in: .whitespaces))
    }
}

/// A collection of DICOM elements indexed by tag.
public struct DICOMDataset: Sendable, Sequence {
    private var storage: [DICOMTag: DICOMElement]

    /// Creates a dataset containing the supplied elements.
    ///
    /// If multiple elements use the same tag, the last element is retained.
    public init(elements: [DICOMElement] = []) {
        storage = Dictionary(elements.map { ($0.tag, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    /// Returns the element for `tag`, if present.
    public subscript(tag: DICOMTag) -> DICOMElement? { storage[tag] }

    /// Returns an iterator over the dataset's elements.
    public func makeIterator() -> Dictionary<DICOMTag, DICOMElement>.Values.Iterator {
        storage.values.makeIterator()
    }
}

/// A DICOM transfer syntax identified by its UID.
public enum TransferSyntax: Sendable, Equatable {
    /// Implicit VR Little Endian (`1.2.840.10008.1.2`).
    case implicitVRLittleEndian
    /// Explicit VR Little Endian (`1.2.840.10008.1.2.1`).
    case explicitVRLittleEndian
    /// Explicit VR Big Endian (`1.2.840.10008.1.2.2`).
    case explicitVRBigEndian
    /// A transfer syntax not modelled by DICOMKit.
    case unknown(String)

    /// The transfer syntax UID.
    public var uid: String {
        switch self {
        case .implicitVRLittleEndian: "1.2.840.10008.1.2"
        case .explicitVRLittleEndian: "1.2.840.10008.1.2.1"
        case .explicitVRBigEndian: "1.2.840.10008.1.2.2"
        case .unknown(let uid): uid
        }
    }

    init(uid: String) {
        switch uid {
        case Self.implicitVRLittleEndian.uid: self = .implicitVRLittleEndian
        case Self.explicitVRLittleEndian.uid: self = .explicitVRLittleEndian
        case Self.explicitVRBigEndian.uid: self = .explicitVRBigEndian
        default: self = .unknown(uid)
        }
    }
}

/// Errors produced while reading a DICOM Part 10 file.
public enum DICOMError: Error, Sendable, Equatable {
    /// The file doesn't contain the 128-byte preamble followed by `DICM`.
    case missingPart10Preamble
    /// The input ended before the declared structure could be read.
    case truncatedData
    /// An Explicit VR element contains an unrecognised VR code.
    case invalidVR(String)
    /// The file uses a transfer syntax that the reader doesn't support.
    case unsupportedTransferSyntax(String)
    /// The File Meta Information doesn't contain a Transfer Syntax UID `(0002,0010)`.
    case missingTransferSyntaxUID
    /// A non-sequence element declares an undefined length.
    case unsupportedUndefinedLength(DICOMTag)
    /// A sequence contains an invalid Item or Sequence Delimitation Item.
    case invalidSequenceItem(DICOMTag)
}

/// Errors produced while creating an image from uncompressed DICOM Pixel Data.
public enum DICOMImageError: Error, Sendable, Equatable {
    /// Required image metadata is absent or inconsistent.
    case invalidImageAttributes
    /// The image format is not currently supported by the renderer.
    case unsupportedPixelFormat
    /// The Pixel Data value is shorter than required by its image metadata.
    case truncatedPixelData
    /// A window width of one or less was supplied.
    case invalidWindowWidth
    /// A window center or width that isn't a finite number (`NaN` or infinite) was supplied.
    case invalidWindowSettings
}

/// Uncompressed image data and the DICOM attributes required to render it.
public struct DICOMPixelData: Sendable {
    /// The raw value of `(7FE0,0010)`, including any DICOM padding byte.
    public let value: Data
    /// Image height in pixels.
    public let rows: Int
    /// Image width in pixels.
    public let columns: Int
    /// Number of samples per pixel.
    public let samplesPerPixel: Int
    /// Number of bits allocated for each sample.
    public let bitsAllocated: Int
    /// The photometric interpretation, for example `MONOCHROME2` or `RGB`.
    public let photometricInterpretation: String
    /// The planar configuration, when applicable.
    public let planarConfiguration: Int
    /// Number of bits actually meaningful within each allocated sample.
    ///
    /// Defaults to ``bitsAllocated`` when `(0028,0101)` is absent, per the
    /// DICOM default. Only consulted by the 16-bit monochrome rendering path.
    public let bitsStored: Int
    /// `0` if samples are unsigned integers, `1` if samples are 2's
    /// complement signed integers. Defaults to `0` when `(0028,0103)` is
    /// absent. Only consulted by the 16-bit monochrome rendering path.
    public let pixelRepresentation: Int
    /// The value of `(0028,1053)`, applied as `storedValue * rescaleSlope +
    /// rescaleIntercept` before windowing. Defaults to `1.0` when absent.
    /// Only consulted by the 16-bit monochrome rendering path.
    public let rescaleSlope: Double
    /// The value of `(0028,1052)`, applied as `storedValue * rescaleSlope +
    /// rescaleIntercept` before windowing. Defaults to `0.0` when absent.
    /// Only consulted by the 16-bit monochrome rendering path.
    public let rescaleIntercept: Double
    /// The dataset's suggested Window Center `(0028,1050)`, if present.
    ///
    /// Used by ``cgImage(windowCenter:windowWidth:)`` when the caller doesn't
    /// supply an explicit window center. `nil` if `(0028,1050)` is absent or
    /// unparsable.
    public let defaultWindowCenter: Double?
    /// The dataset's suggested Window Width `(0028,1051)`, if present.
    ///
    /// Used by ``cgImage(windowCenter:windowWidth:)`` when the caller doesn't
    /// supply an explicit window width. `nil` if `(0028,1051)` is absent or
    /// unparsable.
    public let defaultWindowWidth: Double?

    /// Creates uncompressed pixel data and its rendering attributes.
    ///
    /// `bitsStored`, `pixelRepresentation`, `rescaleSlope`, and
    /// `rescaleIntercept` default to the values DICOM specifies when the
    /// corresponding attribute is absent from a dataset, so callers that
    /// don't care about them (for example, 8-bit or `RGB` pixel data) can
    /// omit them entirely.
    init(
        value: Data,
        rows: Int,
        columns: Int,
        samplesPerPixel: Int,
        bitsAllocated: Int,
        photometricInterpretation: String,
        planarConfiguration: Int = 0,
        bitsStored: Int? = nil,
        pixelRepresentation: Int = 0,
        rescaleSlope: Double = 1.0,
        rescaleIntercept: Double = 0.0,
        defaultWindowCenter: Double? = nil,
        defaultWindowWidth: Double? = nil
    ) {
        self.value = value
        self.rows = rows
        self.columns = columns
        self.samplesPerPixel = samplesPerPixel
        self.bitsAllocated = bitsAllocated
        self.photometricInterpretation = photometricInterpretation
        self.planarConfiguration = planarConfiguration
        self.bitsStored = bitsStored ?? bitsAllocated
        self.pixelRepresentation = pixelRepresentation
        self.rescaleSlope = rescaleSlope
        self.rescaleIntercept = rescaleIntercept
        self.defaultWindowCenter = defaultWindowCenter
        self.defaultWindowWidth = defaultWindowWidth
    }

    /// Creates a Core Graphics image for 8-bit monochrome, interleaved RGB,
    /// or 16-bit monochrome data.
    ///
    /// The 8-bit and `RGB` paths render stored bytes directly: they don't
    /// apply ``pixelRepresentation``, ``rescaleSlope``, or
    /// ``rescaleIntercept``. This is a deliberate simplification, since
    /// signed or rescaled 8-bit Pixel Data is essentially unused in
    /// practice.
    ///
    /// For 16-bit monochrome data, each stored sample is masked to
    /// ``bitsStored`` bits, sign-extended if ``pixelRepresentation`` is `1`,
    /// and then rescaled as `storedValue * rescaleSlope + rescaleIntercept`
    /// (for example, to Hounsfield Units for CT) before windowing. `center`
    /// and `width` are therefore expressed in the *rescaled* unit, not in
    /// raw stored values.
    ///
    /// The window used for 16-bit monochrome data is resolved independently
    /// for center and width, in this priority order:
    /// 1. The `windowCenter` / `windowWidth` parameters, if supplied.
    /// 2. ``defaultWindowCenter`` / ``defaultWindowWidth`` (the dataset's
    ///    `(0028,1050)` / `(0028,1051)`), if present.
    /// 3. A window computed from the rescaled data itself: `center =
    ///    (min+max)/2`, `width = max-min`. If every sample has the same
    ///    rescaled value, `width` would be `0`; to avoid throwing
    ///    ``DICOMImageError/invalidWindowWidth`` for that degenerate case,
    ///    a width of `2` is used instead, producing a single-color image
    ///    instead of a crash.
    ///
    /// A caller may supply only one of `windowCenter` / `windowWidth`; the
    /// other is resolved independently through the same priority order (for
    /// example, an explicit `windowCenter` with no `windowWidth` combines
    /// with the dataset's default width, or the computed width if the
    /// dataset has none).
    public func cgImage(windowCenter: Double? = nil, windowWidth: Double? = nil) throws -> CGImage {
        let pixelCount = try checkedPixelCount()
        switch (photometricInterpretation, bitsAllocated) {
        case ("MONOCHROME1", 8), ("MONOCHROME2", 8):
            guard samplesPerPixel == 1 else { throw DICOMImageError.invalidImageAttributes }
            let source = try requiredBytes(pixelCount)
            let pixels = photometricInterpretation == "MONOCHROME1"
                ? Data(source.map { 255 - $0 })
                : source
            return try makeImage(data: pixels, colorSpace: CGColorSpaceCreateDeviceGray(), bitsPerPixel: 8, bytesPerRow: columns)

        case ("RGB", 8):
            guard samplesPerPixel == 3, planarConfiguration == 0 else {
                throw DICOMImageError.unsupportedPixelFormat
            }
            let byteCount = try checkedByteCount(pixelCount, bytesPerSample: 1, samples: 3)
            return try makeImage(data: requiredBytes(byteCount), colorSpace: CGColorSpaceCreateDeviceRGB(), bitsPerPixel: 24, bytesPerRow: columns * 3)

        case ("MONOCHROME1", 16), ("MONOCHROME2", 16):
            guard samplesPerPixel == 1 else { throw DICOMImageError.invalidImageAttributes }
            guard bitsStored >= 1, bitsStored <= bitsAllocated else { throw DICOMImageError.invalidImageAttributes }
            let byteCount = try checkedByteCount(pixelCount, bytesPerSample: 2, samples: 1)
            let source = try requiredBytes(byteCount)
            let samples = rescaledSamples(from: source)

            let (center, width) = resolvedWindow(explicitCenter: windowCenter, explicitWidth: windowWidth, samples: samples)
            guard center.isFinite, width.isFinite else { throw DICOMImageError.invalidWindowSettings }
            guard width > 1 else { throw DICOMImageError.invalidWindowWidth }

            let pixels = Data(samples.map { sample in
                let rendered = windowedSample(sample, center: center, width: width)
                return photometricInterpretation == "MONOCHROME1" ? 255 - rendered : rendered
            })
            return try makeImage(data: pixels, colorSpace: CGColorSpaceCreateDeviceGray(), bitsPerPixel: 8, bytesPerRow: columns)

        default:
            throw DICOMImageError.unsupportedPixelFormat
        }
    }

    /// Decodes little-endian 16-bit samples from `source`, masking each to
    /// ``bitsStored`` bits, sign-extending if ``pixelRepresentation`` is `1`,
    /// and applying ``rescaleSlope`` / ``rescaleIntercept``.
    ///
    /// Callers must have already validated that `bitsStored` is within
    /// `1...bitsAllocated`.
    private func rescaledSamples(from source: Data) -> [Double] {
        let valueMask = (UInt32(1) << bitsStored) - 1
        let signBitMask = UInt32(1) << (bitsStored - 1)
        let signedRange = UInt32(1) << bitsStored
        return stride(from: source.startIndex, to: source.endIndex, by: 2).map { offset in
            let raw = UInt32(UInt16(source[offset]) | (UInt16(source[offset + 1]) << 8))
            let masked = raw & valueMask
            let storedValue: Int64
            if pixelRepresentation == 1, masked & signBitMask != 0 {
                storedValue = Int64(masked) - Int64(signedRange)
            } else {
                storedValue = Int64(masked)
            }
            return Double(storedValue) * rescaleSlope + rescaleIntercept
        }
    }

    /// Resolves the effective window center and width from the explicit
    /// parameters, the dataset defaults, and the rescaled sample data, per
    /// the priority order documented on ``cgImage(windowCenter:windowWidth:)``.
    private func resolvedWindow(explicitCenter: Double?, explicitWidth: Double?, samples: [Double]) -> (center: Double, width: Double) {
        let computed = computedWindow(from: samples)
        let center = explicitCenter ?? defaultWindowCenter ?? computed.center
        let width = explicitWidth ?? defaultWindowWidth ?? computed.width
        return (center, width)
    }

    /// Computes a fallback window from rescaled sample data: `center =
    /// (min+max)/2`, `width = max-min`, substituting `2` for a `width` of
    /// `0` (all samples equal) so the result is always usable without
    /// crashing or throwing.
    private func computedWindow(from samples: [Double]) -> (center: Double, width: Double) {
        guard let first = samples.first else { return (0, 2) }
        var minValue = first
        var maxValue = first
        for sample in samples.dropFirst() {
            if sample < minValue { minValue = sample }
            if sample > maxValue { maxValue = sample }
        }
        let center = (minValue + maxValue) / 2
        let width = maxValue > minValue ? maxValue - minValue : 2
        return (center, width)
    }

    private func checkedPixelCount() throws -> Int {
        guard rows > 0, columns > 0, samplesPerPixel > 0, bitsAllocated > 0 else {
            throw DICOMImageError.invalidImageAttributes
        }
        let result = rows.multipliedReportingOverflow(by: columns)
        guard !result.overflow else { throw DICOMImageError.invalidImageAttributes }
        return result.partialValue
    }

    private func checkedByteCount(_ pixelCount: Int, bytesPerSample: Int, samples: Int) throws -> Int {
        let samplesResult = pixelCount.multipliedReportingOverflow(by: samples)
        let bytesResult = samplesResult.partialValue.multipliedReportingOverflow(by: bytesPerSample)
        guard !samplesResult.overflow, !bytesResult.overflow else { throw DICOMImageError.invalidImageAttributes }
        return bytesResult.partialValue
    }

    private func requiredBytes(_ count: Int) throws -> Data {
        guard value.count >= count else { throw DICOMImageError.truncatedPixelData }
        return value.prefix(count)
    }

    private func makeImage(data: Data, colorSpace: CGColorSpace, bitsPerPixel: Int, bytesPerRow: Int) throws -> CGImage {
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: columns,
                height: rows,
                bitsPerComponent: 8,
                bitsPerPixel: bitsPerPixel,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrderDefault,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else { throw DICOMImageError.invalidImageAttributes }
        return image
    }

    private func windowedSample(_ sample: Double, center: Double, width: Double) -> UInt8 {
        let lower = center - 0.5 - (width - 1) / 2
        let upper = center - 0.5 + (width - 1) / 2
        if sample <= lower { return 0 }
        if sample > upper { return 255 }
        return UInt8(((((sample - (center - 0.5)) / (width - 1)) + 0.5) * 255).rounded())
    }
}

/// A parsed DICOM Part 10 file.
public struct DICOMFile: Sendable {
    /// The File Meta Information dataset (group `0002`).
    public let metaInformation: DICOMDataset
    /// The main DICOM dataset.
    public let dataset: DICOMDataset
    /// The transfer syntax declared by the File Meta Information.
    public let transferSyntax: TransferSyntax

    /// The uncompressed Pixel Data and its rendering attributes.
    ///
    /// `nil` if `(7FE0,0010)` Pixel Data is absent, or if any of the
    /// following required attributes is absent: Rows `(0028,0010)`, Columns
    /// `(0028,0011)`, Samples per Pixel `(0028,0002)`, Bits Allocated
    /// `(0028,0100)`, or Photometric Interpretation `(0028,0004)`. Because
    /// both causes produce the same `nil` result, this property alone can't
    /// distinguish "no Pixel Data in this file" from "Pixel Data is present
    /// but its metadata is incomplete"; inspect `dataset[.pixelData]`
    /// directly if that distinction matters.
    ///
    /// Planar Configuration, Bits Stored, Pixel Representation, Rescale
    /// Slope, Rescale Intercept, Window Center, and Window Width are optional
    /// and fall back to their DICOM default (or `nil`, for the window
    /// values) when absent, so their absence never causes this property to
    /// return `nil`.
    public var pixelData: DICOMPixelData? {
        guard let value = dataset[.pixelData]?.value,
              let rows = dataset[.rows]?.uint16Value,
              let columns = dataset[.columns]?.uint16Value,
              let samplesPerPixel = dataset[.samplesPerPixel]?.uint16Value,
              let bitsAllocated = dataset[.bitsAllocated]?.uint16Value,
              let photometricInterpretation = dataset[.photometricInterpretation]?.stringValue else {
            return nil
        }
        return DICOMPixelData(
            value: value,
            rows: Int(rows),
            columns: Int(columns),
            samplesPerPixel: Int(samplesPerPixel),
            bitsAllocated: Int(bitsAllocated),
            photometricInterpretation: photometricInterpretation,
            planarConfiguration: Int(dataset[.planarConfiguration]?.uint16Value ?? 0),
            bitsStored: dataset[.bitsStored]?.uint16Value.map(Int.init),
            pixelRepresentation: Int(dataset[.pixelRepresentation]?.uint16Value ?? 0),
            rescaleSlope: dataset[.rescaleSlope]?.doubleValue ?? 1.0,
            rescaleIntercept: dataset[.rescaleIntercept]?.doubleValue ?? 0.0,
            defaultWindowCenter: dataset[.windowCenter]?.doubleValue,
            defaultWindowWidth: dataset[.windowWidth]?.doubleValue
        )
    }

    /// Parses a DICOM Part 10 file from memory.
    ///
    /// The reader supports Explicit VR Little Endian and Implicit VR Little
    /// Endian datasets, including defined-length and undefined-length sequences.
    ///
    /// - Parameter data: The complete contents of a DICOM Part 10 file.
    /// - Throws: ``DICOMError`` if the file is malformed or uses an unsupported syntax.
    public init(data input: Data) throws {
        // `Data` slices retain the absolute indices of their underlying buffer,
        // so a slice such as `buffer[500...]` has `startIndex == 500`. Reading
        // it with fixed offsets (like the preamble check below, or the `Reader`
        // that follows) would either trap on an out-of-bounds index or silently
        // read the wrong bytes. Copying into a fresh, zero-based buffer here
        // makes every subsequent offset in this initializer and in `Reader`
        // safe regardless of what kind of `Data` the caller passed in.
        let data = Data(input)
        guard data.count >= 132, data[128...131] == Data("DICM".utf8) else {
            throw DICOMError.missingPart10Preamble
        }

        var reader = Reader(data: data, offset: 132)
        var metaElements: [DICOMElement] = []
        while reader.peekTag()?.group == 0x0002 {
            metaElements.append(try reader.readElement(transferSyntax: .explicitVRLittleEndian))
        }
        metaInformation = DICOMDataset(elements: metaElements)

        guard let uid = metaInformation[.transferSyntaxUID]?.stringValue else {
            throw DICOMError.missingTransferSyntaxUID
        }
        transferSyntax = TransferSyntax(uid: uid)
        guard transferSyntax == .explicitVRLittleEndian || transferSyntax == .implicitVRLittleEndian else {
            throw DICOMError.unsupportedTransferSyntax(uid)
        }

        dataset = DICOMDataset(elements: try reader.readDataset(transferSyntax: transferSyntax))
    }
}

private struct Reader {
    let data: Data
    var offset: Int

    mutating func readDataset(transferSyntax: TransferSyntax, endingAt endOffset: Int? = nil) throws -> [DICOMElement] {
        var elements: [DICOMElement] = []
        while true {
            if let endOffset {
                guard offset <= endOffset else { throw DICOMError.truncatedData }
                if offset == endOffset { return elements }
            }
            guard offset < data.count else {
                guard endOffset == nil else { throw DICOMError.truncatedData }
                return elements
            }
            elements.append(try readElement(transferSyntax: transferSyntax))
        }
    }

    mutating func readElement(transferSyntax: TransferSyntax) throws -> DICOMElement {
        let tag = try readTag()
        let vr: DICOMVR
        let length: UInt32

        switch transferSyntax {
        case .explicitVRLittleEndian:
            let vrText = String(bytes: try readData(count: 2), encoding: .ascii) ?? ""
            guard let parsedVR = DICOMVR(rawValue: vrText) else { throw DICOMError.invalidVR(vrText) }
            vr = parsedVR
            if vr.uses32BitLength {
                _ = try readUInt16()
                length = try readUInt32()
            } else {
                length = UInt32(try readUInt16())
            }
        case .implicitVRLittleEndian:
            // Read the length before resolving the VR: when a tag isn't in
            // DICOMDictionary and its length is undefined (0xFFFFFFFF), the
            // Implicit VR convention is to treat it as a sequence (SQ) rather
            // than as unknown (UN), since UN elements cannot have undefined
            // length under this reader (see `unsupportedUndefinedLength`).
            // This lets sequences outside the small built-in dictionary
            // (e.g. Referenced Image Sequence) still be parsed.
            length = try readUInt32()
            vr = DICOMDictionary.vr(for: tag) ?? (length == .max ? .SQ : .UN)
        default:
            throw DICOMError.unsupportedTransferSyntax(transferSyntax.uid)
        }

        if vr == .SQ {
            return DICOMElement(tag: tag, vr: vr, value: Data(), sequenceItems: try readSequence(transferSyntax: transferSyntax, length: length))
        }
        guard length != .max else { throw DICOMError.unsupportedUndefinedLength(tag) }
        return DICOMElement(tag: tag, vr: vr, value: try readData(count: Int(length)))
    }

    mutating func readSequence(transferSyntax: TransferSyntax, length: UInt32) throws -> [DICOMDataset] {
        let endOffset: Int?
        if length == .max {
            endOffset = nil
        } else {
            let candidate = offset + Int(length)
            guard candidate <= data.count else { throw DICOMError.truncatedData }
            endOffset = candidate
        }

        var items: [DICOMDataset] = []
        while offset < data.count {
            if let endOffset, offset == endOffset { return items }
            let itemTag = try readTag()
            let itemLength = try readUInt32()
            if itemTag == DICOMTag(group: 0xFFFE, element: 0xE0DD) {
                guard endOffset == nil, itemLength == 0 else { throw DICOMError.invalidSequenceItem(itemTag) }
                return items
            }
            guard itemTag == DICOMTag(group: 0xFFFE, element: 0xE000) else {
                throw DICOMError.invalidSequenceItem(itemTag)
            }

            let itemElements: [DICOMElement]
            if itemLength == .max {
                itemElements = try readUndefinedLengthItem(transferSyntax: transferSyntax)
            } else {
                let itemEndOffset = offset + Int(itemLength)
                guard itemEndOffset <= data.count else { throw DICOMError.truncatedData }
                itemElements = try readDataset(transferSyntax: transferSyntax, endingAt: itemEndOffset)
            }
            items.append(DICOMDataset(elements: itemElements))
        }
        if let endOffset, offset == endOffset { return items }
        throw DICOMError.truncatedData
    }

    mutating func readUndefinedLengthItem(transferSyntax: TransferSyntax) throws -> [DICOMElement] {
        var elements: [DICOMElement] = []
        while offset < data.count {
            if peekTag() == DICOMTag(group: 0xFFFE, element: 0xE00D) {
                _ = try readTag()
                guard try readUInt32() == 0 else { throw DICOMError.truncatedData }
                return elements
            }
            elements.append(try readElement(transferSyntax: transferSyntax))
        }
        throw DICOMError.truncatedData
    }

    func peekTag() -> DICOMTag? {
        guard offset + 4 <= data.count else { return nil }
        return DICOMTag(
            group: UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8),
            element: UInt16(data[offset + 2]) | (UInt16(data[offset + 3]) << 8)
        )
    }

    mutating func readTag() throws -> DICOMTag {
        DICOMTag(group: try readUInt16(), element: try readUInt16())
    }

    mutating func readUInt16() throws -> UInt16 {
        let value = try readData(count: 2)
        return UInt16(value[value.startIndex]) | (UInt16(value[value.startIndex + 1]) << 8)
    }

    mutating func readUInt32() throws -> UInt32 {
        let value = try readData(count: 4)
        return UInt32(value[value.startIndex])
            | (UInt32(value[value.startIndex + 1]) << 8)
            | (UInt32(value[value.startIndex + 2]) << 16)
            | (UInt32(value[value.startIndex + 3]) << 24)
    }

    mutating func readData(count: Int) throws -> Data {
        guard count >= 0, count <= data.count - offset else { throw DICOMError.truncatedData }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }
}

private enum DICOMDictionary {
    static func vr(for tag: DICOMTag) -> DICOMVR? {
        switch tag {
        case .transferSyntaxUID, .referencedSOPClassUID: .UI
        case .patientName: .PN
        case .rows, .columns, .samplesPerPixel, .planarConfiguration, .bitsAllocated,
             .bitsStored, .highBit, .pixelRepresentation: .US
        case .photometricInterpretation: .CS
        case .pixelData: .OW
        case .windowCenter, .windowWidth, .rescaleIntercept, .rescaleSlope: .DS
        case .referencedStudySequence: .SQ
        default: nil
        }
    }
}
