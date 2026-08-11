import Foundation
import CoreGraphics

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
    /// The photometric interpretation, for example ``PhotometricInterpretation/monochrome2`` or ``PhotometricInterpretation/rgb``.
    public let photometricInterpretation: PhotometricInterpretation
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
    /// omit them entirely. Public so callers can render pixel data they've
    /// assembled themselves, independently of ``DICOMFile``.
    public init(
        value: Data,
        rows: Int,
        columns: Int,
        samplesPerPixel: Int,
        bitsAllocated: Int,
        photometricInterpretation: PhotometricInterpretation,
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
        case (.monochrome1, 8), (.monochrome2, 8):
            guard samplesPerPixel == 1 else { throw DICOMImageError.invalidImageAttributes }
            let source = try requiredBytes(pixelCount)
            let pixels = photometricInterpretation == .monochrome1
                ? Data(source.map { 255 - $0 })
                : source
            return try makeImage(data: pixels, colorSpace: CGColorSpaceCreateDeviceGray(), bitsPerPixel: 8, bytesPerRow: columns)

        case (.rgb, 8):
            // Samples per Pixel other than 3 is inconsistent with RGB under
            // the DICOM standard itself; Planar Configuration 1 is valid
            // DICOM, just not a layout this renderer implements.
            guard samplesPerPixel == 3 else { throw DICOMImageError.invalidImageAttributes }
            let byteCount = try checkedByteCount(pixelCount, bytesPerSample: 1, samples: 3)
            let source = try requiredBytes(byteCount)
            let interleaved: Data
            switch planarConfiguration {
            case 0: interleaved = source
            case 1:
                var output = Data(count: byteCount)
                for pixel in 0..<pixelCount {
                    output[pixel * 3] = source[pixel]
                    output[pixel * 3 + 1] = source[pixelCount + pixel]
                    output[pixel * 3 + 2] = source[pixelCount * 2 + pixel]
                }
                interleaved = output
            default: throw DICOMImageError.unsupportedPixelFormat
            }
            return try makeImage(data: interleaved, colorSpace: CGColorSpaceCreateDeviceRGB(), bitsPerPixel: 24, bytesPerRow: columns * 3)

        case (.monochrome1, 16), (.monochrome2, 16):
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
                return photometricInterpretation == .monochrome1 ? 255 - rendered : rendered
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
    /// `1...bitsAllocated`. `source` may be a `Data` slice with a non-zero
    /// `startIndex`; offsets are resolved relative to it.
    private func rescaledSamples(from source: Data) -> [Double] {
        let valueMask = (UInt32(1) << bitsStored) - 1
        let signBitMask = UInt32(1) << (bitsStored - 1)
        let signedRange = UInt32(1) << bitsStored
        return stride(from: 0, to: source.count, by: 2).map { offset in
            let raw = UInt32(source.littleEndian(at: offset, as: UInt16.self))
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
              ) else { throw DICOMImageError.imageCreationFailed }
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
