import Foundation

/// One region of Sequence of Ultrasound Regions `(0018,6011)`, describing
/// the physical calibration of one sub-area of an ultrasound image
/// (PS3.3 C.8.5.5.1.15).
///
/// Ultrasound images commonly combine several calibrated sub-areas in one
/// frame — a 2D scan plane alongside an M-mode or spectral Doppler trace —
/// each with its own scale, so `(0028,0030)` alone can't describe them.
public struct DICOMUltrasoundRegion: Sendable, Equatable {
    /// A physical unit named by Physical Units X/Y Direction, per
    /// PS3.3 C.8.5.5.1.15.
    public enum PhysicalUnit: UInt16, Sendable, Equatable {
        /// No units.
        case none = 0
        /// Percent (%).
        case percent = 1
        /// Decibels (dB).
        case decibels = 2
        /// Centimeters (cm).
        case centimeters = 3
        /// Seconds (s).
        case seconds = 4
        /// Hertz (Hz).
        case hertz = 5
        /// Decibels per second (dB/s).
        case decibelsPerSecond = 6
        /// Centimeters per second (cm/s).
        case centimetersPerSecond = 7
        /// Square centimeters (cm²).
        case squareCentimeters = 8
        /// Square centimeters per second (cm²/s).
        case squareCentimetersPerSecond = 9
        /// Cubic centimeters (cm³).
        case cubicCentimeters = 10
        /// Cubic centimeters per second (cm³/s).
        case cubicCentimetersPerSecond = 11
        /// Degrees (°).
        case degrees = 12
    }

    /// Region Location Min X0 `(0018,6018)`: the 0-based column of the
    /// region's left edge.
    public let minX0: Int
    /// Region Location Min Y0 `(0018,601A)`: the 0-based row of the
    /// region's top edge.
    public let minY0: Int
    /// Region Location Max X1 `(0018,601C)`: the 0-based column of the
    /// region's right edge.
    public let maxX1: Int
    /// Region Location Max Y1 `(0018,601E)`: the 0-based row of the
    /// region's bottom edge.
    public let maxY1: Int
    /// Reference Pixel X0 `(0018,6020)`.
    public let referencePixelX0: Int?
    /// Reference Pixel Y0 `(0018,6022)`.
    public let referencePixelY0: Int?
    /// Physical Units X Direction `(0018,6024)`.
    public let physicalUnitsX: PhysicalUnit?
    /// Physical Units Y Direction `(0018,6026)`.
    public let physicalUnitsY: PhysicalUnit?
    /// Physical Delta X `(0018,602C)`: the physical value per pixel along
    /// the X (column) axis.
    public let physicalDeltaX: Double?
    /// Physical Delta Y `(0018,602E)`: the physical value per pixel along
    /// the Y (row) axis.
    public let physicalDeltaY: Double?
    /// Region Spatial Format `(0018,6012)`.
    public let spatialFormat: UInt16?
    /// Region Data Type `(0018,6014)`.
    public let dataType: UInt16?
    /// Region Flags `(0018,6016)`.
    public let flags: UInt16?

    public init(
        minX0: Int,
        minY0: Int,
        maxX1: Int,
        maxY1: Int,
        referencePixelX0: Int? = nil,
        referencePixelY0: Int? = nil,
        physicalUnitsX: PhysicalUnit? = nil,
        physicalUnitsY: PhysicalUnit? = nil,
        physicalDeltaX: Double? = nil,
        physicalDeltaY: Double? = nil,
        spatialFormat: UInt16? = nil,
        dataType: UInt16? = nil,
        flags: UInt16? = nil
    ) {
        self.minX0 = minX0
        self.minY0 = minY0
        self.maxX1 = maxX1
        self.maxY1 = maxY1
        self.referencePixelX0 = referencePixelX0
        self.referencePixelY0 = referencePixelY0
        self.physicalUnitsX = physicalUnitsX
        self.physicalUnitsY = physicalUnitsY
        self.physicalDeltaX = physicalDeltaX
        self.physicalDeltaY = physicalDeltaY
        self.spatialFormat = spatialFormat
        self.dataType = dataType
        self.flags = flags
    }

    /// Whether `(column, row)` lies within this region, inclusive of both
    /// its min and max bounds.
    public func contains(column: Int, row: Int) -> Bool {
        column >= minX0 && column <= maxX1 && row >= minY0 && row <= maxY1
    }

    /// True only when both axes are calibrated in centimetres with a
    /// nonzero physical delta on each — the only case in which a distance
    /// measurement inside this region is meaningful.
    ///
    /// A region whose X axis reports `.seconds` and Y axis `.centimeters`
    /// is an M-mode or spectral Doppler trace plotted against time, not an
    /// image a length can be measured on, even though one of its two axes
    /// is metric.
    public var isSpatialCalibration: Bool {
        physicalUnitsX == .centimeters && physicalUnitsY == .centimeters
            && (physicalDeltaX ?? 0) != 0 && (physicalDeltaY ?? 0) != 0
    }
}

extension DICOMDataset {
    /// The regions declared by Sequence of Ultrasound Regions `(0018,6011)`.
    ///
    /// Empty when the sequence is absent. An item lacking any of the four
    /// required location bounds is skipped rather than failing the whole
    /// read.
    var ultrasoundRegions: [DICOMUltrasoundRegion] {
        guard let items = self[DICOMTag(group: 0x0018, element: 0x6011)]?.sequenceItems else { return [] }
        return items.compactMap { item in
            guard let minX0 = item[DICOMTag(group: 0x0018, element: 0x6018)]?.uint32Values?.first,
                  let minY0 = item[DICOMTag(group: 0x0018, element: 0x601A)]?.uint32Values?.first,
                  let maxX1 = item[DICOMTag(group: 0x0018, element: 0x601C)]?.uint32Values?.first,
                  let maxY1 = item[DICOMTag(group: 0x0018, element: 0x601E)]?.uint32Values?.first else {
                return nil
            }
            let referencePixelX0 = item[DICOMTag(group: 0x0018, element: 0x6020)]?.int32Values?.first
            let referencePixelY0 = item[DICOMTag(group: 0x0018, element: 0x6022)]?.int32Values?.first
            let physicalUnitsX = item[DICOMTag(group: 0x0018, element: 0x6024)]?.uint16Value
                .flatMap(DICOMUltrasoundRegion.PhysicalUnit.init)
            let physicalUnitsY = item[DICOMTag(group: 0x0018, element: 0x6026)]?.uint16Value
                .flatMap(DICOMUltrasoundRegion.PhysicalUnit.init)
            let physicalDeltaX = item[DICOMTag(group: 0x0018, element: 0x602C)]?.float64Values?.first
            let physicalDeltaY = item[DICOMTag(group: 0x0018, element: 0x602E)]?.float64Values?.first
            return DICOMUltrasoundRegion(
                minX0: Int(minX0),
                minY0: Int(minY0),
                maxX1: Int(maxX1),
                maxY1: Int(maxY1),
                referencePixelX0: referencePixelX0.map(Int.init),
                referencePixelY0: referencePixelY0.map(Int.init),
                physicalUnitsX: physicalUnitsX,
                physicalUnitsY: physicalUnitsY,
                physicalDeltaX: physicalDeltaX,
                physicalDeltaY: physicalDeltaY,
                spatialFormat: item[DICOMTag(group: 0x0018, element: 0x6012)]?.uint16Value,
                dataType: item[DICOMTag(group: 0x0018, element: 0x6014)]?.uint16Value,
                flags: item[DICOMTag(group: 0x0018, element: 0x6016)]?.uint16Value
            )
        }
    }
}
